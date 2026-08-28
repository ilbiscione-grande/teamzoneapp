-- S05 read projection for the five main surfaces. Teamzone6 is not a source or target.

create function internal.get_main_surfaces_for_actor(requested_context_ids uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  requested_count integer;
  allowed_count integer;
  observed_at timestamptz := statement_timestamp();
  result jsonb;
begin
  if actor_id is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;

  if requested_context_ids is null or cardinality(requested_context_ids) = 0
     or cardinality(requested_context_ids) > 50
     or array_position(requested_context_ids, null) is not null then
    raise invalid_parameter_value using message = 'invalid_context_selection';
  end if;

  select count(distinct value) into requested_count
  from unnest(requested_context_ids) value;

  with allowed as (
    select context_id from internal.get_my_contexts_for_actor()
  )
  select count(*) into allowed_count
  from (select distinct value as context_id from unnest(requested_context_ids) value) requested
  join allowed using (context_id);

  if allowed_count <> requested_count then
    raise insufficient_privilege using message = 'context_not_found';
  end if;

  with selected_contexts as materialized (
    select distinct context.context_id, context.club_id, context.club_name,
      context.team_id, context.team_name, context.role_package, context.capabilities
    from internal.get_my_contexts_for_actor() context
    join (select distinct value as context_id from unnest(requested_context_ids) value) requested
      using (context_id)
  ), visible_events as materialized (
    select distinct event_row.id, event_row.club_id, event_row.owning_team_id,
      event_row.title, event_row.event_type, event_row.state, event_row.starts_at,
      event_row.ends_at, event_row.revision
    from core.events event_row
    join core.event_teams relation on relation.event_id = event_row.id
      and relation.club_id = event_row.club_id
    join selected_contexts context on context.club_id = event_row.club_id
      and (context.team_id is null or context.team_id = relation.team_id)
    where event_row.state <> 'cancelled'
  ), next_event as (
    select * from visible_events where starts_at >= observed_at order by starts_at, id limit 1
  ), actor_people as materialized (
    select distinct link.club_id, link.club_person_id
    from core.person_account_links link
    join selected_contexts context on context.club_id = link.club_id
    where link.profile_id = actor_id and link.state = 'active'
  ), own_callups as materialized (
    select distinct callup.id, callup.club_id, callup.event_id, callup.state, callup.revision
    from core.callups callup
    join actor_people person on person.club_id = callup.club_id
      and person.club_person_id = callup.club_person_id
    join visible_events event_row on event_row.id = callup.event_id
    where callup.state <> 'cancelled'
  ), attendance as materialized (
    select fact.status, fact.revision
    from core.attendance_facts fact
    join actor_people person on person.club_id = fact.club_id
      and person.club_person_id = fact.club_person_id
    join visible_events event_row on event_row.id = fact.event_id
  ), action_rows as (
    select distinct context.context_id, context.club_id, context.team_id,
      action.action, action.route
    from selected_contexts context
    cross join lateral (
      values
        ('event.manage', 'create_event', '/calendar'),
        ('club.memberships.manage', 'manage_roster', '/team'),
        ('squad.manage', 'manage_squad', '/calendar'),
        ('attendance.manage', 'record_attendance', '/calendar')
    ) action(required_capability, action, route)
    where action.required_capability = any(context.capabilities)
  ), context_json as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'context_id', context.context_id,
      'club_id', context.club_id,
      'club_name', context.club_name,
      'team_id', context.team_id,
      'team_name', context.team_name,
      'role_package', context.role_package,
      'member_count', case when context.team_id is null then
        (select count(*) from core.club_people person where person.club_id = context.club_id and person.state = 'active')
      else
        (select count(distinct assignment.club_person_id) from core.team_assignments assignment
         where assignment.club_id = context.club_id and assignment.team_id = context.team_id
           and assignment.state = 'active' and assignment.starts_at <= observed_at
           and (assignment.ends_at is null or assignment.ends_at > observed_at)) end
    ) order by context.club_name, context.team_name nulls first, context.context_id), '[]'::jsonb) value
    from selected_contexts context
  ), actions_json as (
    select coalesce(jsonb_agg(jsonb_build_object('action', action, 'route', route,
      'context_id', context_id, 'club_id', club_id, 'team_id', team_id)
      order by context_id, action), '[]'::jsonb) value from action_rows
  )
  select jsonb_build_object(
    'schema_version', 1,
    'generated_at', observed_at,
    'sync_cursor', encode(convert_to('v1:' || observed_at::text || ':' ||
      coalesce((select max(revision) from visible_events), 0)::text || ':' ||
      coalesce((select max(revision) from own_callups), 0)::text || ':' ||
      coalesce((select max(revision) from attendance), 0)::text, 'utf8'), 'base64'),
    'contexts', (select value from context_json),
    'actions', (select value from actions_json),
    'home', jsonb_build_object(
      'upcoming_count', (select count(*) from visible_events where starts_at >= observed_at),
      'pending_callup_count', (select count(*) from own_callups where state = 'pending'),
      'next_event', (select jsonb_build_object('event_id', id, 'title', title,
        'event_type', event_type, 'starts_at', starts_at, 'ends_at', ends_at) from next_event)
    ),
    'calendar', jsonb_build_object(
      'upcoming_count', (select count(*) from visible_events where starts_at >= observed_at),
      'next_event_id', (select id from next_event)
    ),
    'inbox', jsonb_build_object(
      'messages_available', false,
      'pending_notification_count', (select count(*) from internal.notification_outbox outbox
        join actor_people person on person.club_id = outbox.club_id
          and person.club_person_id = outbox.recipient_person_id
        where outbox.recipient_profile_id = actor_id
          and outbox.state in ('pending','processing','failed'))
    ),
    'statistics', jsonb_build_object(
      'present', (select count(*) from attendance where status = 'present'),
      'late', (select count(*) from attendance where status = 'late'),
      'partial', (select count(*) from attendance where status = 'partial'),
      'absent', (select count(*) from attendance where status = 'absent'),
      'unknown', (select count(*) from attendance where status = 'unknown')
    )
  ) into result;

  return result;
end;
$$;

revoke all on function internal.get_main_surfaces_for_actor(uuid[]) from public, anon, authenticated;
grant execute on function internal.get_main_surfaces_for_actor(uuid[]) to authenticated;

create function api.get_main_surfaces(context_ids uuid[])
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select internal.get_main_surfaces_for_actor(context_ids); $$;

revoke all on function api.get_main_surfaces(uuid[]) from public, anon;
grant execute on function api.get_main_surfaces(uuid[]) to authenticated;

insert into internal.migration_provenance(migration_name, source_kind, source_reference)
values ('20260808093425_s05_main_surface_projection', 'greenfield', null);
