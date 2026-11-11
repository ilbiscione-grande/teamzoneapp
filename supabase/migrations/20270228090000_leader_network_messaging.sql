-- Ledare och klubbfunktionärer skriver till alla ledare i klubben
-- (2026-11-11). A club functionary without the messaging area
-- (club.messaging.manage) could message nobody, and a leader only people in
-- their own team. Now anyone with an active leader or club functionary role
-- in a club can message every other leader and club functionary there,
-- whichever team they are in. Nothing else changes: players, guardians and
-- the club-wide messaging area follow the earlier rules.

create or replace function internal.club_leader_network_allowed(actor_profile_id uuid, target_profile_id uuid,
  target_club_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select actor_profile_id is not null and target_profile_id is not null and actor_profile_id <> target_profile_id
    and exists (select 1 from core.person_account_links link
      join core.assignments assignment on assignment.club_id = link.club_id and assignment.club_person_id = link.club_person_id
      where link.profile_id = actor_profile_id and link.club_id = target_club_id and link.state = 'active'
        and assignment.role_package in ('leader', 'club_functionary') and assignment.state = 'active'
        and assignment.starts_at <= now() and (assignment.ends_at is null or assignment.ends_at > now()))
    and exists (select 1 from core.person_account_links link
      join core.assignments assignment on assignment.club_id = link.club_id and assignment.club_person_id = link.club_person_id
      where link.profile_id = target_profile_id and link.club_id = target_club_id and link.state = 'active'
        and assignment.role_package in ('leader', 'club_functionary') and assignment.state = 'active'
        and assignment.starts_at <= now() and (assignment.ends_at is null or assignment.ends_at > now()))
$$;
revoke all on function internal.club_leader_network_allowed(uuid, uuid, uuid) from public, anon, authenticated;

-- As live before, with the leader network.
CREATE OR REPLACE FUNCTION internal.messaging_relationship_allowed(actor_profile_id uuid, target_profile_id uuid, target_club_id uuid, target_team_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select actor_profile_id is not null
    and target_profile_id is not null
    and actor_profile_id <> target_profile_id
    and (exists (
      select 1
      from core.person_account_links actor_link
      join core.assignments actor_assignment
        on actor_assignment.club_id = actor_link.club_id
       and actor_assignment.club_person_id = actor_link.club_person_id
      join core.person_account_links target_link
        on target_link.profile_id = target_profile_id
       and target_link.club_id = actor_assignment.club_id
       and target_link.state = 'active'
      join core.assignments target_assignment
        on target_assignment.club_id = target_link.club_id
       and target_assignment.club_person_id = target_link.club_person_id
      where actor_link.profile_id = actor_profile_id
        and actor_link.state = 'active'
        and actor_assignment.club_id = target_club_id
        and target_assignment.club_id = target_club_id
        and (
          target_team_id is null
          or (
            actor_assignment.team_id = target_team_id
            and target_assignment.team_id = target_team_id
          )
        )
        and actor_assignment.state = 'active'
        and actor_assignment.starts_at <= now()
        and (actor_assignment.ends_at is null or actor_assignment.ends_at > now())
        and target_assignment.state = 'active'
        and target_assignment.starts_at <= now()
        and (target_assignment.ends_at is null or target_assignment.ends_at > now())
        and (
          actor_assignment.role_package = 'leader'
          or (
            actor_assignment.role_package = 'club_functionary'
            and exists (
              select 1
              from core.capability_grants grant_row
              where grant_row.assignment_id = actor_assignment.id
                and grant_row.club_id = actor_assignment.club_id
                and grant_row.capability = 'club.messaging.manage'
                and grant_row.starts_at <= now()
                and (grant_row.ends_at is null or grant_row.ends_at > now())
                and (
                  (grant_row.scope_type = 'club' and grant_row.scope_id = target_club_id)
                  or (
                    target_team_id is not null
                    and grant_row.scope_type = 'team'
                    and grant_row.scope_id = target_team_id
                  )
                )
            )
          )
          or (
            actor_assignment.role_package = 'player'
            and target_assignment.role_package in ('leader', 'guardian')
          )
          or (
            actor_assignment.role_package = 'guardian'
            and target_assignment.role_package = 'leader'
          )
        )
    )
    -- 20270228090000: leaders and functionaries reach each other club-wide.
    or internal.club_leader_network_allowed(actor_profile_id, target_profile_id, target_club_id))
    and not exists (
      select 1
      from core.contact_controls block
      where block.control_type = 'block'
        and block.state = 'active'
        and (
          (block.requester_profile_id = actor_profile_id and block.target_profile_id = target_profile_id)
          or (block.target_profile_id = actor_profile_id and block.requester_profile_id = target_profile_id)
        )
    );
$function$;

-- As live before: leaders and functionaries elsewhere in the club are offered.
CREATE OR REPLACE FUNCTION internal.resolve_allowed_recipients_for_actor(target_context_id uuid, search_text text DEFAULT NULL::text)
 RETURNS TABLE(profile_id uuid, display_name text, role_package text, team_names text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  actor_context record;
begin
  if auth.uid() is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;

  select * into actor_context
  from internal.get_my_contexts_for_actor()
  where context_id = target_context_id;

  if actor_context.context_id is null then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if search_text is not null and length(search_text) > 80 then
    raise invalid_parameter_value using message = 'invalid_search';
  end if;

  return query
  -- One row per person: a leader who is also a functionary shows once.
  select candidate.profile_id, candidate.display_name,
    (array_agg(candidate.role_package order by case candidate.role_package when 'leader' then 0
      when 'club_functionary' then 1 when 'player' then 2 when 'guardian' then 3 else 4 end))[1],
    string_agg(distinct candidate.team_name, ', ' order by candidate.team_name)
  from (
    select link.profile_id,
      coalesce(nullif(btrim(profile.display_name), ''), person.display_name) display_name,
      assignment.role_package,
      team.name team_name
    from core.assignments assignment
    join core.person_account_links link
      on link.club_id = assignment.club_id
     and link.club_person_id = assignment.club_person_id
     and link.state = 'active'
    join core.profiles profile on profile.id = link.profile_id
    join core.club_people person on person.id = link.club_person_id and person.club_id = link.club_id
    left join core.teams team on team.id = assignment.team_id and team.club_id = assignment.club_id
    where assignment.club_id = actor_context.club_id
      and (actor_context.team_id is null or assignment.team_id = actor_context.team_id
        or (assignment.role_package in ('leader', 'club_functionary')
          and internal.club_leader_network_allowed(auth.uid(), link.profile_id, actor_context.club_id)))
      and assignment.state = 'active'
      and assignment.starts_at <= now()
      and (assignment.ends_at is null or assignment.ends_at > now())
      and internal.messaging_relationship_allowed(
        auth.uid(),
        link.profile_id,
        actor_context.club_id,
        actor_context.team_id
      )
  ) candidate
  where search_text is null
    or candidate.display_name ilike
      '%' || replace(replace(left(btrim(search_text), 80), '%', '\%'), '_', '\_') || '%'
      escape '\'
  group by candidate.profile_id, candidate.display_name
  order by candidate.display_name
  limit 50;
end;
$function$;

-- As live before, with the club scope for recipients outside the team.
CREATE OR REPLACE FUNCTION internal.create_thread_for_actor(target_context_id uuid, new_type text, new_subject text, recipient_profile_ids uuid[], idempotency_key uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  scope_team uuid;
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

  -- A recipient outside the context team (a leader elsewhere in the club)
  -- could not read a team-scoped thread: scope it to the club instead.
  scope_team := context_row.team_id;
  if scope_team is not null and exists (
    select 1 from (select distinct value profile_id from unnest(recipient_profile_ids) value) requested
    where not exists (
      select 1 from core.assignments assignment
      join core.person_account_links link on link.club_id = assignment.club_id
        and link.club_person_id = assignment.club_person_id and link.state = 'active'
      where link.profile_id = requested.profile_id and assignment.club_id = context_row.club_id
        and assignment.team_id = scope_team and assignment.state = 'active'
        and assignment.starts_at <= now() and (assignment.ends_at is null or assignment.ends_at > now()))) then
    scope_team := null;
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
      select function_body.thread_id, context_row.club_id, scope_team, 'peer'
      where not exists (
        select 1
        from core.thread_scopes scope
        where scope.thread_id = function_body.thread_id
          and scope.club_id = context_row.club_id
          and scope.team_id is not distinct from scope_team
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
  values (thread_id, context_row.club_id, scope_team, 'owner');
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
$function$;

notify pgrst, 'reload schema';
