create or replace function internal.ensure_guardian_context_for_relation(
  target_relation_id uuid
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  relation_row core.guardian_relations%rowtype;
  target_team_id uuid;
  guardian_assignment_id uuid;
begin
  select * into relation_row
  from core.guardian_relations
  where id=target_relation_id and state='active';
  if relation_row.id is null then
    raise invalid_parameter_value using message='guardian_relation_not_active';
  end if;

  select team_assignment.team_id into target_team_id
  from core.team_assignments team_assignment
  where team_assignment.club_id=relation_row.club_id
    and team_assignment.club_person_id=relation_row.child_person_id
    and team_assignment.state='active'
    and team_assignment.starts_at<=now()
    and (team_assignment.ends_at is null or team_assignment.ends_at>now())
  order by team_assignment.starts_at desc,team_assignment.id desc
  limit 1;
  if target_team_id is null then
    raise invalid_parameter_value using message='guardian_child_team_required';
  end if;

  select assignment.id into guardian_assignment_id
  from core.assignments assignment
  where assignment.club_id=relation_row.club_id
    and assignment.team_id=target_team_id
    and assignment.club_person_id=relation_row.guardian_person_id
    and assignment.role_package='guardian'
    and assignment.state='active'
    and assignment.starts_at<=now()
    and (assignment.ends_at is null or assignment.ends_at>now())
  order by assignment.starts_at desc,assignment.id desc
  limit 1;

  if guardian_assignment_id is null then
    insert into core.assignments(
      club_id,team_id,club_person_id,role_package,state,starts_at,created_by
    ) values (
      relation_row.club_id,target_team_id,relation_row.guardian_person_id,
      'guardian','active',now(),relation_row.created_by
    ) returning id into guardian_assignment_id;
  end if;

  insert into core.capability_grants(
    club_id,assignment_id,capability,scope_type,scope_id,starts_at,created_by
  ) values (
    relation_row.club_id,guardian_assignment_id,'team.roster.view','team',
    target_team_id,now(),relation_row.created_by
  ) on conflict(assignment_id,capability,scope_type,scope_id) do nothing;

  return guardian_assignment_id;
end;
$$;

insert into internal.migration_provenance(
  migration_name,source_kind,source_reference
) values (
  '20260902091951_team05_guardian_context_assignment_name',
  'greenfield',
  'TEAM-05 unambiguous guardian assignment provisioning'
);

notify pgrst,'reload schema';
