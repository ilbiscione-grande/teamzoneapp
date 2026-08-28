insert into core.capability_grants (
  club_id,
  assignment_id,
  capability,
  scope_type,
  scope_id,
  starts_at,
  created_by
)
select
  assignment.club_id,
  assignment.id,
  capability.value,
  'team',
  assignment.team_id,
  greatest(assignment.starts_at, now()),
  assignment.created_by
from core.assignments assignment
cross join (values ('team.roster.view'), ('event.manage')) capability(value)
where assignment.role_package = 'leader'
  and assignment.team_id is not null
  and assignment.state = 'active'
  and assignment.starts_at <= now()
  and (assignment.ends_at is null or assignment.ends_at > now())
on conflict (assignment_id, capability, scope_type, scope_id) do nothing;

insert into internal.migration_provenance (
  migration_name,
  source_kind,
  source_reference
)
values (
  '20260815082049_s07_seed_leader_team_capabilities',
  'greenfield',
  'S07 physical verification: active team leaders need roster read and event management'
);

notify pgrst, 'reload schema';
