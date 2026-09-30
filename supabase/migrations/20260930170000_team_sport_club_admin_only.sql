-- TEAM-11: only club administrators (club-scoped club.memberships.manage)
-- may change which sport a team plays. Team leaders who manage roles keep
-- every other part of the team profile. The roles list tells the client
-- whether the viewer may change the sport.

create or replace function internal.actor_is_club_admin(target_club_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(
  select 1 from core.person_account_links link
  join core.assignments assignment on assignment.club_person_id=link.club_person_id
   and assignment.club_id=link.club_id
  join core.capability_grants grant_row on grant_row.assignment_id=assignment.id
   and grant_row.club_id=assignment.club_id
  where link.profile_id=auth.uid() and link.state='active'
   and assignment.club_id=target_club_id and assignment.state='active'
   and assignment.starts_at<=now() and (assignment.ends_at is null or assignment.ends_at>now())
   and grant_row.capability='club.memberships.manage'
   and grant_row.scope_type='club' and grant_row.scope_id=target_club_id
   and grant_row.starts_at<=now() and (grant_row.ends_at is null or grant_row.ends_at>now()))
$$;
revoke all on function internal.actor_is_club_admin(uuid) from public,anon,authenticated;
grant execute on function internal.actor_is_club_admin(uuid) to authenticated;

do $patch$
declare definition text; patched text;
begin
 definition:=pg_get_functiondef('internal.set_team_sport_for_actor(uuid,uuid,text,uuid)'::regprocedure);
 patched:=replace(definition,
  'perform internal.assert_team_role_manager(target_club_id,target_team_id);',
  'if auth.uid() is null then raise insufficient_privilege using message=''unauthenticated''; end if;
 if not exists(select 1 from core.teams where id=target_team_id and club_id=target_club_id)
  or not internal.actor_is_club_admin(target_club_id) then
  raise insufficient_privilege using message=''club_admin_required''; end if;');
 if patched=definition then raise exception 'set_team_sport_for_actor: patch point not found'; end if;
 execute patched;

 definition:=pg_get_functiondef('internal.list_team_roles_for_actor(uuid,uuid)'::regprocedure);
 patched:=replace(definition,
  '''can_manage'',manages_leaders,',
  '''can_manage'',manages_leaders,
  ''can_set_sport'',internal.actor_is_club_admin(target_club_id),');
 if patched=definition then raise exception 'list_team_roles_for_actor: patch point not found'; end if;
 execute patched;
end$patch$;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
select '20260930170000_team_sport_club_admin_only','greenfield',
 'TEAM-11 only club administrators change a team''s sport'
where not exists(select 1 from internal.migration_provenance
 where migration_name='20260930170000_team_sport_club_admin_only');
notify pgrst,'reload schema';
