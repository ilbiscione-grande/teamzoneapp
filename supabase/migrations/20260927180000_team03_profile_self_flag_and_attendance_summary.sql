-- Support the profile-page restructure: the profile now shows read-only
-- info + attendance/match stats (visible to the person themselves or a
-- manager), while editing and the roster-admin actions move to a separate
-- edit view. Two additions:
-- (1) is_self on the existing person-details projection, so the client
--     knows to show stats without a manager capability.
-- (2) a small per-person attendance summary RPC (training attendance,
--     matches played), gated to the person themselves or a manager.

create or replace function internal.get_roster_person_details_for_actor(
  target_club_id uuid,target_team_id uuid,target_club_person_id uuid
)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); can_manage boolean; actor_role text; result jsonb;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  if not internal.actor_has_capability(target_club_id,target_team_id,'team.roster.view')
     and not internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
  then raise insufficient_privilege using message='not_found'; end if;
  select assignment.role_package into actor_role from core.person_account_links link
  join core.assignments assignment on assignment.club_person_id=link.club_person_id
    and assignment.club_id=link.club_id and assignment.state='active'
    and assignment.starts_at<=now() and (assignment.ends_at is null or assignment.ends_at>now())
  where link.profile_id=actor_id and link.club_id=target_club_id and link.state='active'
    and (assignment.team_id=target_team_id or assignment.team_id is null)
  order by assignment.team_id is not null desc limit 1;
  if actor_role is null or actor_role not in ('player','leader','guardian','club_functionary')
  then raise insufficient_privilege using message='role_not_supported'; end if;
  can_manage:=internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
    or internal.actor_has_capability(target_club_id,null,'club.memberships.manage');
  select jsonb_strip_nulls(jsonb_build_object(
    'club_person_id',person.id,'display_name',person.display_name,'age_class',person.age_class,
    'team_id',team.id,'team_name',team.name,'assignment_state',assignment.state,
    'person_revision',case when can_manage and person.status='active' and assignment.state='active'
      then person.revision else null end,
    'safeguarding_required',case when can_manage and person.status='active'
      then person.safeguarding_required else null end,
    'representation_available',case when can_manage and person.status='active'
      then person.representation_available else null end,
    'account_linked',case when can_manage then exists(
      select 1 from core.person_account_links link
      where link.club_person_id=person.id and link.club_id=person.club_id and link.state='active'
    ) else null end,
    'is_self',internal.actor_owns_club_person(target_club_id,person.id),
    'management',case when can_manage then jsonb_build_object('provenance',person.provenance,
      'assignment_starts_at',assignment.starts_at,'assignment_ends_at',assignment.ends_at,
      'assignment_revision',assignment.revision) else null end
  )) into result from core.club_people person
  join lateral(select item.* from core.team_assignments item where item.club_id=person.club_id
    and item.club_person_id=person.id and item.team_id=target_team_id
    order by item.state='active' desc,item.starts_at desc,item.id desc limit 1) assignment on true
  join core.teams team on team.id=assignment.team_id and team.club_id=assignment.club_id
  where person.id=target_club_person_id and person.club_id=target_club_id
    and person.status in ('active','ended');
  if result is null then raise insufficient_privilege using message='not_found'; end if;
  return result;
end
$$;

create function internal.get_person_attendance_summary_for_actor(
  target_club_id uuid,
  target_team_id uuid,
  target_club_person_id uuid
)
returns table(
  trainings_total int,
  trainings_attended int,
  matches_total int,
  matches_played int
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
begin
  if actor_id is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;
  if not internal.actor_has_capability(
      target_club_id, target_team_id, 'club.memberships.manage'
    )
    and not internal.actor_owns_club_person(target_club_id, target_club_person_id)
  then
    raise insufficient_privilege using message = 'not_found';
  end if;

  return query
  select
    count(*) filter (where event_row.event_type = 'training')::int,
    count(*) filter (
      where event_row.event_type = 'training'
        and fact.status in ('present', 'late', 'partial')
    )::int,
    count(*) filter (where event_row.event_type = 'match')::int,
    count(*) filter (
      where event_row.event_type = 'match'
        and fact.status in ('present', 'late', 'partial')
    )::int
  from core.callups callup
  join core.events event_row
    on event_row.id = callup.event_id and event_row.club_id = target_club_id
  left join core.attendance_facts fact
    on fact.event_id = callup.event_id
    and fact.club_person_id = callup.club_person_id
    and fact.club_id = target_club_id
  where callup.club_id = target_club_id
    and callup.club_person_id = target_club_person_id
    and callup.state <> 'cancelled'
    and event_row.owning_team_id = target_team_id
    and event_row.state <> 'cancelled'
    and event_row.starts_at < now();
end;
$$;

create function api.get_person_attendance_summary(
  target_club_id uuid,
  target_team_id uuid,
  target_club_person_id uuid
)
returns table(
  trainings_total int,
  trainings_attended int,
  matches_total int,
  matches_played int
)
language sql
stable
security invoker
set search_path = ''
as $$
  select * from internal.get_person_attendance_summary_for_actor(
    target_club_id, target_team_id, target_club_person_id
  )
$$;

revoke all on function internal.get_person_attendance_summary_for_actor(uuid,uuid,uuid)
  from public,anon,authenticated;
grant execute on function internal.get_person_attendance_summary_for_actor(uuid,uuid,uuid)
  to authenticated;
revoke all on function api.get_person_attendance_summary(uuid,uuid,uuid)
  from public,anon;
grant execute on function api.get_person_attendance_summary(uuid,uuid,uuid)
  to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260927180000_team03_profile_self_flag_and_attendance_summary','greenfield','TEAM-03 profile restructure: is_self flag + per-person attendance summary');

notify pgrst,'reload schema';
