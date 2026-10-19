-- UX review 2026-10-19: who is called up is private by default (CAL-10),
-- but CAL-11's rewrite of get_event_squad dropped the filter, so every
-- member saw everyone's callups. The filter is back, and a team now has a
-- default that each event can override (or return to).

create table if not exists core.team_callup_visibility (
  team_id uuid primary key references core.teams(id) on delete cascade,
  club_id uuid not null references core.clubs(id),
  show_to_members boolean not null,
  updated_by uuid references core.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);
alter table core.team_callup_visibility enable row level security;
revoke all on core.team_callup_visibility from public, anon, authenticated;

-- As in 20260907170000, with the visibility filter of 20260902104510 and
-- the team's default.
create or replace function internal.get_event_squad_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare event_row core.events%rowtype;squad core.squad_revisions%rowtype;
 can_manage boolean;show_to_members boolean;visibility_source text;visibility_revision bigint;team_shows boolean;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 select * into event_row from core.events where id=target_event_id;
 if event_row.id is null or not internal.actor_can_read_event(target_event_id)
 then raise insufficient_privilege using message='not_found';end if;
 can_manage:=internal.actor_can_manage_squad(target_event_id);
 -- CAL-10 visibility: the event's choice, else the team's, else private.
 select visibility.show_to_members,visibility.revision into show_to_members,visibility_revision
 from core.event_callup_visibility visibility where visibility.event_id=target_event_id;
 select setting.show_to_members into team_shows from core.team_callup_visibility setting
 where setting.team_id=event_row.owning_team_id;
 visibility_source:=case when show_to_members is not null then 'event'
  when team_shows is not null then 'team' else 'default' end;
 show_to_members:=coalesce(show_to_members,team_shows,false);
 visibility_revision:=coalesce(visibility_revision,0);
 select * into squad from core.squad_revisions where event_id=target_event_id order by revision desc limit 1;
 return jsonb_build_object('event_id',target_event_id,'squad_revision_id',squad.id,
  'squad_revision',squad.revision,'squad_state',coalesce(squad.state,'empty'),
  'selection_source',squad.selection_source,'selection_context',coalesce(squad.selection_context,'{}'::jsonb),
  'dispatch_kind',coalesce(squad.dispatch_kind,'initial'),
  'show_callups_to_members',show_to_members,
  'callup_visibility_revision',visibility_revision,
  'callup_visibility_source',visibility_source,
  'team_shows_callups',coalesce(team_shows,false),
  'members',coalesce((select jsonb_agg(jsonb_build_object('person_id',member.club_person_id,
   'name',person.display_name,'selection_state',member.selection_state,'source',member.source)order by person.display_name)
   from core.squad_members member join core.club_people person on person.id=member.club_person_id
   where member.squad_revision_id=squad.id and(can_manage or show_to_members
    or internal.actor_represents_club_person(event_row.club_id,member.club_person_id))),'[]'::jsonb),
  'callups',coalesce((select jsonb_agg(jsonb_build_object('callup_id',callup.id,
   'person_id',callup.club_person_id,'name',person.display_name,'state',callup.state,
   'revision',callup.revision,'expires_at',callup.expires_at,'delivery_state',coalesce(sent.state,'pending'),
   'last_reminded_at',callup.last_reminded_at,'reminder_count',callup.reminder_count,
   'reminder_delivery_state',reminder.state,'can_respond',(response_context->>'can_respond')::boolean,
   'acting_as_person_id',response_context->>'acting_as_person_id','response_role',response_context->>'response_role')
   order by person.display_name) from core.callups callup join core.club_people person on person.id=callup.club_person_id
   cross join lateral internal.actor_callup_response_context(callup.id)response(response_context)
   left join lateral(select state from internal.notification_outbox where aggregate_id=callup.id
    and event_type in('callup.callup.sent.v1','callup.callup.late_sent.v1') order by created_at desc limit 1)sent on true
   left join lateral(select state from internal.notification_outbox where aggregate_id=callup.id
    and event_type='callup.callup.reminded.v2' order by created_at desc limit 1)reminder on true
   where callup.event_id=target_event_id and(can_manage or show_to_members
    or internal.actor_represents_club_person(event_row.club_id,callup.club_person_id))),'[]'::jsonb),
  'attendance',coalesce((select jsonb_agg(jsonb_build_object('person_id',callup.club_person_id,
   'name',person.display_name,'status',coalesce(attendance.status,'unknown'),'minutes',attendance.minutes,
   'revision',coalesce(attendance.revision,0))order by person.display_name) from core.callups callup
   join core.club_people person on person.id=callup.club_person_id left join core.attendance_facts attendance
    on attendance.event_id=callup.event_id and attendance.club_person_id=callup.club_person_id
   where callup.event_id=target_event_id and callup.state<>'cancelled' and(can_manage
    or internal.actor_represents_club_person(event_row.club_id,callup.club_person_id))),'[]'::jsonb),
  'roster',coalesce((select jsonb_agg(jsonb_build_object(
   'person_id',assignment.club_person_id,'name',person.display_name,
   'team_id',assignment.team_id,'team_name',team.name,'role_package',assignment.role_package,
   'in_draft',member.club_person_id is not null,
   'callup_id',callup.id,'callup_state',callup.state,
   'callup_expires_at',callup.expires_at,'callup_last_reminded_at',callup.last_reminded_at,
   'attendance_status',attendance.status,'attendance_revision',coalesce(attendance.revision,0),
   'can_respond',(roster_response.response_context->>'can_respond')::boolean,
   'response_role',roster_response.response_context->>'response_role')
   order by team.created_at,assignment.role_package desc,person.display_name)
   from core.assignments assignment
   join core.club_people person on person.id=assignment.club_person_id and person.club_id=assignment.club_id
   join core.teams team on team.id=assignment.team_id and team.club_id=assignment.club_id
   join core.event_teams relation on relation.event_id=target_event_id and relation.club_id=assignment.club_id
    and relation.team_id=assignment.team_id
   left join core.squad_members member on member.squad_revision_id=squad.id and member.club_person_id=assignment.club_person_id
   left join core.callups callup on callup.event_id=target_event_id and callup.club_person_id=assignment.club_person_id
    and callup.state<>'cancelled' and(can_manage or show_to_members
     or internal.actor_represents_club_person(event_row.club_id,assignment.club_person_id))
   left join core.attendance_facts attendance on attendance.event_id=target_event_id
    and attendance.club_person_id=assignment.club_person_id and(can_manage
     or internal.actor_represents_club_person(event_row.club_id,assignment.club_person_id))
   left join lateral internal.actor_callup_response_context(callup.id)roster_response(response_context) on true
   where assignment.club_id=event_row.club_id and assignment.state='active'
    and assignment.role_package in('player','leader') and person.status='active'
    and assignment.starts_at<=event_row.starts_at and(assignment.ends_at is null or assignment.ends_at>event_row.starts_at)
  ),'[]'::jsonb),
  'caller_actions',case when internal.actor_can_manage_squad(target_event_id)
   then array['save_squad','lock_squad','send_callups','cancel_callup','remind_callup',
    'set_callup_visibility']::text[]
   else array[]::text[] end||case when internal.actor_can_manage_attendance(target_event_id)
   then array['record_attendance']::text[] else array[]::text[] end);
end;$$;

-- As in 20260928104134: attendance only for those who manage the squad or
-- attendance, and for the person (or a guardian) themselves.
create or replace function internal.get_event_attendance_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare sees_all boolean;
begin
 if auth.uid() is null or not internal.actor_can_read_event(target_event_id) then
  raise insufficient_privilege using message='not_found';
 end if;
 sees_all:=internal.actor_can_manage_squad(target_event_id)
  or internal.actor_can_manage_attendance(target_event_id);
 return coalesce((
   select jsonb_agg(jsonb_build_object(
     'person_id',person.id,'name',person.display_name,
     'status',coalesce(fact.status,'unknown'),'minutes',fact.minutes,
     'revision',coalesce(fact.revision,0)) order by person.display_name)
   from core.club_people person
   left join core.attendance_facts fact on fact.club_person_id=person.id
     and fact.event_id=target_event_id and fact.club_id=person.club_id
   where person.club_id=(select event_row.club_id from core.events event_row where event_row.id=target_event_id)
     and (fact.id is not null or exists(select 1 from core.callups callup
       where callup.event_id=target_event_id and callup.club_person_id=person.id
         and callup.state<>'cancelled'))
     and (sees_all or internal.actor_represents_club_person(person.club_id,person.id))
  ),'[]'::jsonb);
end;
$$;

-- The team's default, for the team's members; set by those who call up.
create or replace function internal.get_team_callup_visibility_for_actor(target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare team_row core.teams%rowtype;
begin
  select * into team_row from core.teams where id = target_team_id;
  if team_row.id is null or not exists (select 1 from core.person_account_links link
      where link.club_id = team_row.club_id and link.profile_id = auth.uid() and link.state = 'active') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return jsonb_build_object(
    'show_to_members', coalesce((select setting.show_to_members from core.team_callup_visibility setting
      where setting.team_id = team_row.id), false),
    'can_change', internal.actor_has_capability(team_row.club_id, team_row.id, 'event.squad.manage')
      or internal.actor_has_capability(team_row.club_id, team_row.id, 'team.roster.manage')
      or internal.actor_manages_club(team_row.club_id));
end;$$;

create or replace function internal.set_team_callup_visibility_for_actor(target_team_id uuid, show_to_members boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare team_row core.teams%rowtype;
begin
  select * into team_row from core.teams where id = target_team_id;
  if team_row.id is null or not (internal.actor_has_capability(team_row.club_id, team_row.id, 'event.squad.manage')
      or internal.actor_has_capability(team_row.club_id, team_row.id, 'team.roster.manage')
      or internal.actor_manages_club(team_row.club_id)) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if show_to_members is null then raise invalid_parameter_value using message = 'invalid_input'; end if;
  insert into core.team_callup_visibility(team_id, club_id, show_to_members, updated_by)
  values (team_row.id, team_row.club_id, set_team_callup_visibility_for_actor.show_to_members, auth.uid())
  on conflict (team_id) do update set show_to_members = excluded.show_to_members,
    updated_by = excluded.updated_by, updated_at = now();
end;$$;

-- An event back to its team's default.
create or replace function internal.clear_event_callup_visibility_for_actor(target_event_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not internal.actor_can_manage_squad(target_event_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  delete from core.event_callup_visibility where event_id = target_event_id;
end;$$;

create or replace function api.get_team_callup_visibility(target_team_id uuid)
returns jsonb language sql security invoker set search_path = '' as
$$select internal.get_team_callup_visibility_for_actor(target_team_id)$$;
create or replace function api.set_team_callup_visibility(target_team_id uuid, show_to_members boolean)
returns void language sql security invoker set search_path = '' as
$$select internal.set_team_callup_visibility_for_actor(target_team_id, show_to_members)$$;
create or replace function api.clear_event_callup_visibility(target_event_id uuid)
returns void language sql security invoker set search_path = '' as
$$select internal.clear_event_callup_visibility_for_actor(target_event_id)$$;

revoke all on function internal.get_team_callup_visibility_for_actor(uuid),
  internal.set_team_callup_visibility_for_actor(uuid, boolean),
  internal.clear_event_callup_visibility_for_actor(uuid),
  api.get_team_callup_visibility(uuid), api.set_team_callup_visibility(uuid, boolean),
  api.clear_event_callup_visibility(uuid)
  from public, anon, authenticated;
grant execute on function internal.get_team_callup_visibility_for_actor(uuid),
  internal.set_team_callup_visibility_for_actor(uuid, boolean),
  internal.clear_event_callup_visibility_for_actor(uuid),
  api.get_team_callup_visibility(uuid), api.set_team_callup_visibility(uuid, boolean),
  api.clear_event_callup_visibility(uuid)
  to authenticated;

insert into internal.migration_provenance (migration_name, source_kind, source_reference)
select '20261112090000_callup_visibility_by_team', 'greenfield', 'UX: callup visibility filter restored, team default and event override'
where not exists (select 1 from internal.migration_provenance where migration_name = '20261112090000_callup_visibility_by_team');
notify pgrst, 'reload schema';
