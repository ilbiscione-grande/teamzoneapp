-- Kallelser till ledargruppers möten. A booked group meeting calls up
-- everyone in the group at once, so each member gets a push and the
-- notification ("Ny kallelse · Möte · Herrsektionen · tid") and can answer.
-- Deltagare lists the group's members instead of the holding team's players
-- and leaders, and anyone active in the club can be found and called up
-- too. Those who manage leader groups manage the meeting's callups.

-- Anyone with an active role in the club can be called to a group meeting;
-- other activities are as before.
create or replace function internal.leader_group_meeting_eligibility(target_event_id uuid, target_person_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('kind', 'team_assignment', 'id', assignment.id, 'team_id', assignment.team_id,
    'starts_at', assignment.starts_at, 'ends_at', assignment.ends_at)
  from core.events event_row
  join core.assignments assignment on assignment.club_id = event_row.club_id
    and assignment.club_person_id = target_person_id and assignment.state = 'active'
    and assignment.starts_at <= greatest(now(), event_row.starts_at) and (assignment.ends_at is null or assignment.ends_at > event_row.starts_at)
  join core.club_people person on person.id = assignment.club_person_id and person.status = 'active'
  where event_row.id = target_event_id
  order by (assignment.role_package = 'leader') desc, (assignment.team_id is null), assignment.starts_at desc
  limit 1
$$;

-- Deltagare for a group meeting: the group's members, with the teams they
-- lead, called or not, as the team roster shows a team's people.
create or replace function internal.leader_group_meeting_roster(
  target_event_id uuid, squad_id uuid, can_manage boolean, show_to_members boolean
)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'person_id', person.id, 'name', person.display_name,
    'team_id', coalesce(led.team_id, event_row.owning_team_id),
    'team_name', coalesce(led.names, ''),
    'role_package', 'leader',
    'in_draft', member.club_person_id is not null,
    'callup_id', callup.id, 'callup_state', callup.state,
    'callup_expires_at', callup.expires_at, 'callup_last_reminded_at', callup.last_reminded_at,
    'attendance_status', attendance.status, 'attendance_revision', coalesce(attendance.revision, 0),
    'can_respond', (response.response_context->>'can_respond')::boolean,
    'response_role', response.response_context->>'response_role'
  ) order by person.display_name), '[]'::jsonb)
  from core.leader_group_events group_event
  join core.events event_row on event_row.id = group_event.event_id
  cross join lateral internal.leader_group_member_people(group_event.group_id) group_member
  join core.club_people person on person.id = group_member.club_person_id
  left join lateral (
    select (array_agg(team.id order by team.name))[1] as team_id,
      string_agg(distinct team.name, ', ') as names
    from core.assignments assignment join core.teams team on team.id = assignment.team_id
    where assignment.club_id = event_row.club_id and assignment.club_person_id = person.id
      and assignment.role_package = 'leader' and assignment.state = 'active'
      and assignment.starts_at <= now() and (assignment.ends_at is null or assignment.ends_at > now())
  ) led on true
  left join core.squad_members member on member.squad_revision_id = squad_id and member.club_person_id = person.id
  left join core.callups callup on callup.event_id = target_event_id and callup.club_person_id = person.id
    and callup.state <> 'cancelled'
    and (can_manage or show_to_members or internal.actor_represents_club_person(event_row.club_id, person.id))
  left join core.attendance_facts attendance on attendance.event_id = target_event_id
    and attendance.club_person_id = person.id
    and (can_manage or internal.actor_represents_club_person(event_row.club_id, person.id))
  left join lateral internal.actor_callup_response_context(callup.id) response(response_context) on true
  where group_event.event_id = target_event_id
$$;

do $patch$
declare
  def text;
  patched text;
begin
  -- Eligibility: a group meeting asks the group rule instead.
  def := pg_get_functiondef('internal.person_eligibility_at_event(uuid,uuid)'::regprocedure);
  patched := regexp_replace(def, 'select coalesce\(',
    'select case when exists (select 1 from core.leader_group_events group_event where group_event.event_id = target_event_id) then internal.leader_group_meeting_eligibility(target_event_id, target_person_id) else coalesce(');
  patched := regexp_replace(patched, '\)\s*;\s*\$function\$\s*$', ') end; $function$');
  if patched = def or position(') end; $function$' in patched) = 0 then
    raise exception 'person_eligibility_at_event not patched';
  end if;
  execute patched;

  -- Callups and attendance: those who manage leader groups.
  def := pg_get_functiondef('internal.actor_has_event_capability(uuid,text)'::regprocedure);
  patched := replace(def, 'select auth.uid() is not null and exists(',
    'select auth.uid() is not null and ((required_capability in (''event.squad.manage'', ''event.attendance.manage'') and internal.actor_can_manage_leader_group_meeting(target_event_id)) or exists(');
  patched := regexp_replace(patched, '\$function\$\s*$', ') $function$');
  if patched = def or position('actor_can_manage_leader_group_meeting' in patched) = 0 then
    raise exception 'actor_has_event_capability not patched';
  end if;
  execute patched;

  -- Deltagare: the group's members instead of the holding team.
  def := pg_get_functiondef('internal.get_event_squad_for_actor(uuid)'::regprocedure);
  patched := replace(def, '''roster'',coalesce((select jsonb_agg(',
    '''roster'',case when exists(select 1 from core.leader_group_events group_event where group_event.event_id=target_event_id) then internal.leader_group_meeting_roster(target_event_id,squad.id,can_manage,show_to_members) else coalesce((select jsonb_agg(');
  -- The stored body may have CRLF line ends.
  patched := regexp_replace(patched, '\),''\[\]''::jsonb\),(\s+)''caller_actions''',
    '),''[]''::jsonb) end,\1''caller_actions''');
  if position('leader_group_meeting_roster' in patched) = 0 or position('::jsonb) end,' in patched) = 0 then
    raise exception 'get_event_squad_for_actor not patched';
  end if;
  execute patched;

  -- The push names the group instead of the holding team.
  def := pg_get_functiondef('internal.push_message_for_outbox(uuid)'::regprocedure);
  patched := replace(def,
    'select name into team_name from core.teams where id = event_row.owning_team_id;',
    'select coalesce((select group_row.name from core.leader_group_events group_event join core.leader_groups group_row on group_row.id = group_event.group_id where group_event.event_id = event_row.id), (select team.name from core.teams team where team.id = event_row.owning_team_id)) into team_name;');
  if patched = def then raise exception 'push_message_for_outbox not patched'; end if;
  execute patched;
end
$patch$;

-- Calls up the group's members to a newly booked meeting: the same draft,
-- lock and send as Deltagare, done by the one who booked it.
create or replace function internal.call_up_leader_group_meeting(target_event_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  event_row core.events%rowtype;
  member_ids uuid[];
  draft jsonb;
begin
  select * into event_row from core.events where id = target_event_id;
  if event_row.starts_at <= now() + interval '5 minutes' then return; end if;
  select array_agg(distinct group_member.club_person_id) into member_ids
  from core.leader_group_events group_event
  cross join lateral internal.leader_group_member_people(group_event.group_id) group_member
  where group_event.event_id = target_event_id
    and internal.person_eligibility_at_event(target_event_id, group_member.club_person_id) is not null;
  if member_ids is null then return; end if;
  draft := internal.save_squad_draft_v2_for_actor(target_event_id, member_ids, 'manual', '{}'::jsonb, null,
    gen_random_uuid());
  perform internal.lock_squad_for_actor(target_event_id, (draft->>'revision')::bigint, gen_random_uuid());
  perform internal.send_callups_for_actor((draft->>'squad_revision_id')::uuid, event_row.starts_at,
    gen_random_uuid());
end
$$;

do $patch$
declare
  def text;
  patched text;
begin
  def := pg_get_functiondef(
    'internal.create_leader_group_meeting_for_actor(uuid,text,timestamptz,timestamptz,text,text,text,uuid)'::regprocedure);
  patched := replace(def, '  existing_result := jsonb_build_object(''event_id'', new_event_id);',
    '  perform internal.call_up_leader_group_meeting(new_event_id);
  existing_result := jsonb_build_object(''event_id'', new_event_id);');
  if patched = def then raise exception 'create_leader_group_meeting_for_actor not patched'; end if;
  execute patched;
end
$patch$;

revoke all on function
  internal.leader_group_meeting_eligibility(uuid, uuid),
  internal.leader_group_meeting_roster(uuid, uuid, boolean, boolean),
  internal.call_up_leader_group_meeting(uuid)
from public, anon, authenticated;

notify pgrst, 'reload schema';
