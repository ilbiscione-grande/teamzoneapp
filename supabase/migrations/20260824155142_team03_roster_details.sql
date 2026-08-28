-- TEAM-03 role-minimized roster member details.

create function internal.get_roster_person_details_for_actor(
  target_club_id uuid,target_team_id uuid,target_club_person_id uuid
)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); can_manage boolean; actor_role text; result jsonb;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  if not internal.actor_has_capability(target_club_id,target_team_id,'team.roster.view')
     and not internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage') then
    raise insufficient_privilege using message='not_found';
  end if;
  select assignment.role_package into actor_role
  from core.person_account_links link
  join core.assignments assignment on assignment.club_person_id=link.club_person_id
    and assignment.club_id=link.club_id and assignment.state='active'
    and assignment.starts_at<=now() and (assignment.ends_at is null or assignment.ends_at>now())
  where link.profile_id=actor_id and link.club_id=target_club_id and link.state='active'
    and (assignment.team_id=target_team_id or assignment.team_id is null)
  order by assignment.team_id is not null desc limit 1;
  if actor_role is null or actor_role not in ('player','leader','guardian','club_functionary') then
    raise insufficient_privilege using message='role_not_supported';
  end if;
  can_manage:=internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
    or internal.actor_has_capability(target_club_id,null,'club.memberships.manage');
  select jsonb_strip_nulls(jsonb_build_object(
    'club_person_id',person.id,'display_name',person.display_name,
    'age_class',person.age_class,'team_id',team.id,'team_name',team.name,
    'assignment_state',assignment.state,
    'safeguarding_required',case when can_manage then person.safeguarding_required else null end,
    'management',case when can_manage then jsonb_build_object(
      'provenance',person.provenance,'assignment_starts_at',assignment.starts_at,
      'assignment_ends_at',assignment.ends_at,'assignment_revision',assignment.revision
    ) else null end
  )) into result
  from core.club_people person
  join lateral(select item.* from core.team_assignments item
    where item.club_id=person.club_id and item.club_person_id=person.id
      and item.team_id=target_team_id
    order by item.state='active' desc,item.starts_at desc,item.id desc limit 1
  ) assignment on true
  join core.teams team on team.id=assignment.team_id and team.club_id=assignment.club_id
  where person.id=target_club_person_id and person.club_id=target_club_id
    and person.status='active';
  if result is null then raise insufficient_privilege using message='not_found'; end if;
  return result;
end
$$;

create function api.get_roster_person_details(
  target_club_id uuid,target_team_id uuid,target_club_person_id uuid
)
returns jsonb language sql stable security invoker set search_path=''
as $$select internal.get_roster_person_details_for_actor(target_club_id,target_team_id,target_club_person_id)$$;

revoke all on function internal.get_roster_person_details_for_actor(uuid,uuid,uuid),
  api.get_roster_person_details(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function internal.get_roster_person_details_for_actor(uuid,uuid,uuid),
  api.get_roster_person_details(uuid,uuid,uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260824155142_team03_roster_details','greenfield','TEAM-03 role-minimized roster member details');
