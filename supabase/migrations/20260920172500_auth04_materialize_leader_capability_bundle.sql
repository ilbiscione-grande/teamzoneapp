-- An approved membership application creates an explicit role assignment.
-- Materialize the baseline team-leader capabilities as grant rows whenever
-- such an assignment becomes active; authorization continues to depend on
-- capabilities, never on the role label alone.

create or replace function internal.materialize_leader_capabilities_from_assignment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.role_package = 'leader'
     and new.team_id is not null
     and new.state = 'active'
     and new.starts_at <= now()
     and (new.ends_at is null or new.ends_at > now())
  then
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
      new.club_id,
      new.id,
      capability.value,
      'team',
      new.team_id,
      greatest(new.starts_at, now()),
      new.ends_at,
      new.created_by
    from unnest(array[
      'team.roster.view',
      'team.roster.manage',
      'event.manage'
    ]::text[]) capability(value)
    on conflict(assignment_id, capability, scope_type, scope_id) do nothing;
  end if;
  return new;
end
$$;

revoke all on function internal.materialize_leader_capabilities_from_assignment()
from public, anon, authenticated;

drop trigger if exists assignments_materialize_leader_capabilities
on core.assignments;
create trigger assignments_materialize_leader_capabilities
after insert or update of role_package, state, team_id, starts_at, ends_at
on core.assignments
for each row execute function internal.materialize_leader_capabilities_from_assignment();

-- Reconcile active leaders approved after the earlier one-time seed
-- migrations. Existing explicit grants and explicit revocations are retained:
-- only entirely missing rows are inserted.
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
  capability.value,
  'team',
  assignment.team_id,
  greatest(assignment.starts_at, now()),
  assignment.ends_at,
  assignment.created_by
from core.assignments assignment
cross join unnest(array[
  'team.roster.view',
  'team.roster.manage',
  'event.manage'
]::text[]) capability(value)
where assignment.role_package = 'leader'
  and assignment.team_id is not null
  and assignment.state = 'active'
  and assignment.starts_at <= now()
  and (assignment.ends_at is null or assignment.ends_at > now())
on conflict(assignment_id, capability, scope_type, scope_id) do nothing;

insert into internal.migration_provenance(
  migration_name,
  source_kind,
  source_reference
) values (
  '20260920172500_auth04_materialize_leader_capability_bundle',
  'greenfield',
  'AUTH-04 physical approval verification: leader role lacked capability grants'
);

notify pgrst, 'reload schema';
