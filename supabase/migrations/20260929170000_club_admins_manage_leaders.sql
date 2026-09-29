-- TEAM-10 follow-up. The rollout gave team.leaders.manage only to holders of
-- club-scoped event.manage, but about half of the club functionaries hold
-- event.manage per team, so teams were left without anyone who could open
-- the permission panel. Whoever administers memberships for the whole club
-- (club-scoped club.memberships.manage) now also manages leaders and squads
-- club-wide. Their event capabilities are deliberately not widened.

insert into core.capability_grants(club_id,assignment_id,capability,scope_type,scope_id,starts_at,ends_at,created_by)
select g.club_id,g.assignment_id,capability.value,'club',g.scope_id,g.starts_at,g.ends_at,g.created_by
from core.capability_grants g
join core.assignments a on a.id=g.assignment_id and a.state='active'
cross join unnest(array['team.leaders.manage','team.roster.manage']::text[]) capability(value)
where g.capability='club.memberships.manage' and g.scope_type='club'
 and (g.ends_at is null or g.ends_at>now())
on conflict(assignment_id,capability,scope_type,scope_id) do nothing;

-- Future club administrators (new clubs, additional teams, board mandates).
create function internal.expand_club_membership_admin()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.capability='club.memberships.manage' and new.scope_type='club' then
  insert into core.capability_grants(club_id,assignment_id,capability,scope_type,scope_id,starts_at,ends_at,created_by)
  select new.club_id,new.assignment_id,capability.value,'club',new.scope_id,new.starts_at,new.ends_at,new.created_by
  from unnest(array['team.leaders.manage','team.roster.manage']::text[]) capability(value)
  on conflict(assignment_id,capability,scope_type,scope_id) do nothing;
 end if;
 return new;
end$$;
create trigger capability_grants_expand_club_membership_admin after insert on core.capability_grants
for each row execute function internal.expand_club_membership_admin();
revoke all on function internal.expand_club_membership_admin() from public,anon,authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260929170000_club_admins_manage_leaders','greenfield','TEAM-10 follow-up: club membership admins manage leaders');
notify pgrst,'reload schema';
