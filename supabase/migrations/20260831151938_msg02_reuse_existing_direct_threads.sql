-- Reuse an existing active direct conversation for the same two profiles.
-- A transaction-scoped advisory lock serializes first-contact attempts for the
-- canonical club/profile pair, preventing concurrent duplicate threads.

create or replace function internal.create_thread_for_actor(
  target_context_id uuid,
  new_type text,
  new_subject text,
  recipient_profile_ids uuid[],
  idempotency_key uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
<<function_body>>
declare
  actor_id uuid := auth.uid();
  context_row record;
  thread_id uuid := gen_random_uuid();
  recipient_id uuid;
  recipient_count integer;
  allowed_count integer;
  existing jsonb;
  actor_person uuid;
  pair_low uuid;
  pair_high uuid;
begin
  if actor_id is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;

  select dedup.result
  into existing
  from internal.command_deduplication dedup
  where dedup.actor_profile_id = actor_id
    and dedup.command_type = 'message.thread.created.v1'
    and dedup.idempotency_key = create_thread_for_actor.idempotency_key;
  if existing is not null then
    return (existing ->> 'thread_id')::uuid;
  end if;

  select *
  into context_row
  from internal.get_my_contexts_for_actor()
  where context_id = target_context_id;

  if context_row.context_id is null or new_type not in ('group', 'direct') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if recipient_profile_ids is null
     or cardinality(recipient_profile_ids) < 1
     or cardinality(recipient_profile_ids) > 50
     or array_position(recipient_profile_ids, null) is not null
     or (new_type = 'group' and length(btrim(coalesce(new_subject, ''))) not between 1 and 120) then
    raise invalid_parameter_value using message = 'invalid_recipients';
  end if;

  select count(distinct value), (array_agg(distinct value order by value))[1]
  into recipient_count, recipient_id
  from unnest(recipient_profile_ids) value;
  select count(*)
  into allowed_count
  from (select distinct value profile_id from unnest(recipient_profile_ids) value) requested
  where internal.messaging_relationship_allowed(
    actor_id,
    requested.profile_id,
    context_row.club_id,
    context_row.team_id
  );
  if recipient_count <> allowed_count or (new_type = 'direct' and recipient_count <> 1) then
    raise insufficient_privilege using message = 'invalid_recipients';
  end if;

  if new_type = 'direct' then
    pair_low := least(actor_id, recipient_id);
    pair_high := greatest(actor_id, recipient_id);
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        context_row.club_id::text || ':' || pair_low::text || ':' || pair_high::text,
        0
      )
    );

    -- A concurrent request may have completed while this request waited.
    select dedup.result
    into existing
    from internal.command_deduplication dedup
    where dedup.actor_profile_id = actor_id
      and dedup.command_type = 'message.thread.created.v1'
      and dedup.idempotency_key = create_thread_for_actor.idempotency_key;
    if existing is not null then
      return (existing ->> 'thread_id')::uuid;
    end if;

    select candidate.thread_id
    into thread_id
    from (
      select thread.id thread_id,
             coalesce(max(message.created_at), thread.created_at) last_activity
      from core.message_threads thread
      join core.thread_participants participant
        on participant.thread_id = thread.id
       and participant.state = 'active'
      left join core.messages message
        on message.thread_id = thread.id
      where thread.club_id = context_row.club_id
        and thread.thread_type = 'direct'
        and thread.state = 'active'
      group by thread.id
      having count(distinct participant.profile_id) = 2
         and count(distinct participant.profile_id) filter (
           where participant.profile_id in (actor_id, recipient_id)
         ) = 2
    ) candidate
    order by candidate.last_activity desc, candidate.thread_id
    limit 1;

    if thread_id is not null then
      insert into core.thread_scopes(thread_id, club_id, team_id, scope_role)
      select function_body.thread_id, context_row.club_id, context_row.team_id, 'peer'
      where not exists (
        select 1
        from core.thread_scopes scope
        where scope.thread_id = function_body.thread_id
          and scope.club_id = context_row.club_id
          and scope.team_id is not distinct from context_row.team_id
      );
      insert into internal.command_deduplication(
        actor_profile_id, idempotency_key, command_type, result
      ) values (
        actor_id,
        idempotency_key,
        'message.thread.created.v1',
        jsonb_build_object('thread_id', function_body.thread_id, 'reused', true)
      );
      insert into audit.command_events(
        club_id, actor_profile_id, command_type, aggregate_type,
        aggregate_id, aggregate_revision, metadata
      )
      select context_row.club_id, actor_id, 'message.thread.reused.v1',
             'message_thread', thread.id, thread.revision,
             jsonb_build_object('type', 'direct', 'recipient_count', 1)
      from core.message_threads thread
      where thread.id = function_body.thread_id;
      return function_body.thread_id;
    end if;

    thread_id := gen_random_uuid();
  end if;

  select link.club_person_id
  into actor_person
  from core.person_account_links link
  where link.profile_id = actor_id
    and link.club_id = context_row.club_id
    and link.state = 'active';

  insert into core.message_threads(id, club_id, thread_type, subject, created_by)
  values (
    thread_id,
    context_row.club_id,
    new_type,
    case when new_type = 'group' then btrim(new_subject) end,
    actor_id
  );
  insert into core.thread_scopes(thread_id, club_id, team_id, scope_role)
  values (thread_id, context_row.club_id, context_row.team_id, 'owner');
  insert into core.thread_participants(
    thread_id, profile_id, club_id, club_person_id, participant_role
  ) values (thread_id, actor_id, context_row.club_id, actor_person, 'creator');
  insert into core.thread_participants(
    thread_id, profile_id, club_id, club_person_id, participant_role
  )
  select distinct on (link.profile_id)
    thread_id, link.profile_id, link.club_id, link.club_person_id, 'member'
  from core.person_account_links link
  where link.profile_id = any(recipient_profile_ids)
    and link.club_id = context_row.club_id
    and link.state = 'active'
  order by link.profile_id, link.created_at desc;
  insert into internal.command_deduplication(
    actor_profile_id, idempotency_key, command_type, result
  ) values (
    actor_id,
    idempotency_key,
    'message.thread.created.v1',
    jsonb_build_object('thread_id', thread_id, 'reused', false)
  );
  insert into audit.command_events(
    club_id, actor_profile_id, command_type, aggregate_type,
    aggregate_id, aggregate_revision, metadata
  ) values (
    context_row.club_id,
    actor_id,
    'message.thread.created.v1',
    'message_thread',
    thread_id,
    1,
    jsonb_build_object('type', new_type, 'recipient_count', recipient_count)
  );
  return thread_id;
end;
$$;

revoke all on function internal.create_thread_for_actor(uuid, text, text, uuid[], uuid)
from public, anon, authenticated;
grant execute on function internal.create_thread_for_actor(uuid, text, text, uuid[], uuid)
to authenticated;

comment on function internal.create_thread_for_actor(uuid, text, text, uuid[], uuid) is
  'Creates group threads and atomically reuses the latest active same-club direct thread for an authorized profile pair.';
