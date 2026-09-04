-- MSG-03 hardening: materialize participants from the same current assignments
-- that authorize announcement creation and recipient selection.
create or replace function internal.create_announcement_for_actor(
  target_context_id uuid,
  new_subject text,
  recipient_profile_ids uuid[],
  idempotency_key uuid
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  context_row record;
  thread_id uuid := gen_random_uuid();
  actor_person uuid;
  recipient_count integer;
  allowed_count integer;
  materialized_count integer;
  existing jsonb;
begin
  if actor_id is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;
  select result into existing
  from internal.command_deduplication d
  where d.actor_profile_id = actor_id
    and d.command_type = 'message.announcement.created.v1'
    and d.idempotency_key = create_announcement_for_actor.idempotency_key;
  if existing is not null then
    return (existing ->> 'thread_id')::uuid;
  end if;

  select * into context_row
  from internal.get_my_contexts_for_actor()
  where context_id = target_context_id;
  if context_row.context_id is null
     or length(btrim(coalesce(new_subject, ''))) not between 1 and 120
     or recipient_profile_ids is null
     or cardinality(recipient_profile_ids) < 1
     or cardinality(recipient_profile_ids) > 50
     or array_position(recipient_profile_ids, null) is not null then
    raise insufficient_privilege using message = 'not_found';
  end if;

  select link.club_person_id into actor_person
  from core.person_account_links link
  join core.assignments assignment
    on assignment.club_id = link.club_id
   and assignment.club_person_id = link.club_person_id
  where link.profile_id = actor_id
    and link.club_id = context_row.club_id
    and link.state = 'active'
    and assignment.state = 'active'
    and assignment.starts_at <= now()
    and (assignment.ends_at is null or assignment.ends_at > now())
    and (context_row.team_id is null or assignment.team_id = context_row.team_id)
    and assignment.role_package in ('leader', 'club_functionary')
  order by assignment.starts_at desc, link.created_at desc
  limit 1;
  if actor_person is null then
    raise insufficient_privilege using message = 'not_found';
  end if;

  select count(distinct value) into recipient_count
  from unnest(recipient_profile_ids) value;
  select count(*) into allowed_count
  from (select distinct value profile_id from unnest(recipient_profile_ids) value) requested
  where internal.messaging_relationship_allowed(
    actor_id,
    requested.profile_id,
    context_row.club_id,
    context_row.team_id
  );
  if recipient_count <> allowed_count then
    raise insufficient_privilege using message = 'invalid_recipients';
  end if;

  insert into core.message_threads(id, club_id, thread_type, subject, created_by)
  values(thread_id, context_row.club_id, 'announcement', btrim(new_subject), actor_id);
  insert into core.thread_scopes(thread_id, club_id, team_id, scope_role)
  values(thread_id, context_row.club_id, context_row.team_id, 'owner');
  insert into core.thread_participants(
    thread_id,
    profile_id,
    club_id,
    club_person_id,
    participant_role
  ) values(
    thread_id,
    actor_id,
    context_row.club_id,
    actor_person,
    'creator'
  );

  with eligible as (
    select distinct on (link.profile_id)
      link.profile_id,
      link.club_id,
      link.club_person_id
    from core.person_account_links link
    join core.assignments assignment
      on assignment.club_id = link.club_id
     and assignment.club_person_id = link.club_person_id
    where link.profile_id = any(recipient_profile_ids)
      and link.club_id = context_row.club_id
      and link.state = 'active'
      and assignment.state = 'active'
      and assignment.starts_at <= now()
      and (assignment.ends_at is null or assignment.ends_at > now())
      and (context_row.team_id is null or assignment.team_id = context_row.team_id)
    order by link.profile_id, assignment.starts_at desc, link.created_at desc
  )
  insert into core.thread_participants(
    thread_id,
    profile_id,
    club_id,
    club_person_id,
    participant_role
  )
  select thread_id, profile_id, club_id, club_person_id, 'member'
  from eligible;
  get diagnostics materialized_count = row_count;
  if materialized_count <> recipient_count then
    raise insufficient_privilege using message = 'relationship_changed';
  end if;

  insert into internal.command_deduplication(
    actor_profile_id,
    idempotency_key,
    command_type,
    result
  ) values(
    actor_id,
    idempotency_key,
    'message.announcement.created.v1',
    jsonb_build_object('thread_id', thread_id)
  );
  insert into audit.command_events(
    club_id,
    actor_profile_id,
    command_type,
    aggregate_type,
    aggregate_id,
    aggregate_revision,
    metadata
  ) values(
    context_row.club_id,
    actor_id,
    'message.announcement.created.v1',
    'message_thread',
    thread_id,
    1,
    jsonb_build_object('recipient_count', recipient_count)
  );
  return thread_id;
end;
$$;

insert into internal.migration_provenance(migration_name, source_kind, source_reference)
values(
  '20260828103629_msg03_bind_announcement_participants_to_assignments',
  'greenfield',
  'MSG-03 current-assignment participant materialization'
);
