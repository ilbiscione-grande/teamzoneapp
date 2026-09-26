-- Restore the capability used by the completed MSG-01 physical revocation
-- walkthrough. The existing grant row is reactivated so its identity and
-- revision history remain intact.

do $$
declare
  target_assignment_id uuid;
  affected integer;
begin
  select assignment.id
  into target_assignment_id
  from auth.users account
  join core.person_account_links link
    on link.profile_id = account.id
   and link.state = 'active'
  join core.assignments assignment
    on assignment.club_id = link.club_id
   and assignment.club_person_id = link.club_person_id
   and assignment.role_package = 'leader'
   and assignment.state = 'active'
   and assignment.starts_at <= now()
   and (assignment.ends_at is null or assignment.ends_at > now())
  join core.teams team
    on team.id = assignment.team_id
   and team.club_id = assignment.club_id
  where lower(account.email) = 'coach.emilson+tzleader@gmail.com'
    and team.name = 'Thomas lag'
  order by assignment.starts_at desc, assignment.id
  limit 1;

  if target_assignment_id is null then
    raise exception 'MSG-01 test leader assignment was not found';
  end if;

  update core.capability_grants grant_row
  set starts_at = now(),
      ends_at = null,
      revision = grant_row.revision + 1
  where grant_row.assignment_id = target_assignment_id
    and grant_row.capability = 'team.roster.view'
    and grant_row.scope_type = 'team'
    and grant_row.ends_at is not null;

  get diagnostics affected = row_count;
  if affected <> 1 then
    raise exception 'Expected exactly one revoked MSG-01 roster-view grant, got %', affected;
  end if;
end
$$;

insert into internal.migration_provenance(
  migration_name,
  source_kind,
  source_reference
) values (
  '20260920180500_msg01_restore_test_leader_roster_view',
  'greenfield',
  'MSG-01 cleanup after successful physical capability revoke verification'
);

notify pgrst, 'reload schema';
