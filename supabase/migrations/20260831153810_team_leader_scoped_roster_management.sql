-- Leaders manage their own team roster without receiving club-wide membership
-- administration. Existing roster commands historically ask for
-- club.memberships.manage in a team scope; actor_has_capability maps that
-- specific team-scoped check to the narrower team.roster.manage grant.

insert into core.capability_grants(
  club_id,
  assignment_id,
  capability,
  scope_type,
  scope_id,
  starts_at,
  ends_at,
  created_by
)
select
  assignment.club_id,
  assignment.id,
  'team.roster.manage',
  'team',
  assignment.team_id,
  greatest(assignment.starts_at, now()),
  assignment.ends_at,
  assignment.created_by
from core.assignments assignment
where assignment.role_package = 'leader'
  and assignment.team_id is not null
  and assignment.state = 'active'
  and assignment.starts_at <= now()
  and (assignment.ends_at is null or assignment.ends_at > now())
on conflict(assignment_id, capability, scope_type, scope_id) do update
set starts_at = least(core.capability_grants.starts_at, excluded.starts_at),
    ends_at = excluded.ends_at,
    revision = core.capability_grants.revision + 1;

create or replace function internal.actor_has_capability(
  target_club_id uuid,
  target_team_id uuid,
  required_capability text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and exists (
    select 1
    from core.person_account_links link
    join core.assignments assignment
      on assignment.club_person_id = link.club_person_id
     and assignment.club_id = link.club_id
    join core.capability_grants grant_row
      on grant_row.assignment_id = assignment.id
     and grant_row.club_id = assignment.club_id
    where link.profile_id = auth.uid()
      and link.state = 'active'
      and assignment.state = 'active'
      and assignment.starts_at <= now()
      and (assignment.ends_at is null or assignment.ends_at > now())
      and assignment.club_id = target_club_id
      and (
        grant_row.capability = required_capability
        or (
          required_capability = 'club.memberships.manage'
          and target_team_id is not null
          and grant_row.capability = 'team.roster.manage'
          and grant_row.scope_type = 'team'
        )
      )
      and grant_row.starts_at <= now()
      and (grant_row.ends_at is null or grant_row.ends_at > now())
      and (
        (grant_row.scope_type = 'club' and grant_row.scope_id = target_club_id)
        or (grant_row.scope_type = 'team' and grant_row.scope_id = target_team_id)
      )
  );
$$;

revoke all on function internal.actor_has_capability(uuid, uuid, text)
from public, anon, authenticated;

insert into internal.migration_provenance(
  migration_name,
  source_kind,
  source_reference
)
values (
  '20260831153810_team_leader_scoped_roster_management',
  'greenfield',
  'REL-02 leader phone verification: least-privilege team roster management'
)
on conflict do nothing;

notify pgrst, 'reload schema';
