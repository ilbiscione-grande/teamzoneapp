-- TEAM-11: every squad entry opens the member profile, leaders included.
-- Leaders and team-scoped functionaries have no home-team assignment (only a
-- role assignment), so the profile lookup falls back to their active role in
-- this team. 'home_member' tells the client whether player-only actions
-- (move, representation, archive, attendance) apply.

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
    'home_member',assignment.home,
    'person_revision',case when can_manage and person.status='active' and assignment.state='active'
      then person.revision else null end,
    'safeguarding_required',case when can_manage and person.status='active'
      then person.safeguarding_required else null end,
    'representation_available',case when can_manage and person.status='active' and assignment.home
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
  join lateral(
    select * from (
      (select item.team_id,item.state,item.starts_at,item.ends_at,item.revision,true as home
       from core.team_assignments item where item.club_id=person.club_id
         and item.club_person_id=person.id and item.team_id=target_team_id
       order by item.state='active' desc,item.starts_at desc,item.id desc limit 1)
      union all
      (select role.team_id,role.state,role.starts_at,role.ends_at,null::bigint,false
       from core.assignments role where role.club_id=person.club_id
         and role.club_person_id=person.id and role.team_id=target_team_id
         and role.role_package in ('leader','club_functionary') and role.state='active'
         and role.starts_at<=now() and (role.ends_at is null or role.ends_at>now())
       order by role.starts_at limit 1)
    ) candidates order by home desc limit 1
  ) assignment on true
  join core.teams team on team.id=assignment.team_id and team.club_id=person.club_id
  where person.id=target_club_person_id and person.club_id=target_club_id
    and person.status in ('active','ended');
  if result is null then raise insufficient_privilege using message='not_found'; end if;
  return result;
end
$$;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260929180000_team_member_profile_for_leaders','greenfield',
  'TEAM-11 member profile resolves leaders through their team role');
notify pgrst,'reload schema';
