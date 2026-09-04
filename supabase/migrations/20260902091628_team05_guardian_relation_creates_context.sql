-- An active guardian relation must also yield a least-privilege team context.

alter function internal.accept_guardian_invite_for_actor(text,uuid)
  rename to accept_guardian_invite_and_link_for_actor;

revoke all on function internal.accept_guardian_invite_and_link_for_actor(text,uuid)
  from public,anon,authenticated;

create function internal.ensure_guardian_context_for_relation(
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
  assignment_id uuid;
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

  select assignment.id into assignment_id
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

  if assignment_id is null then
    insert into core.assignments(
      club_id,team_id,club_person_id,role_package,state,starts_at,created_by
    ) values (
      relation_row.club_id,target_team_id,relation_row.guardian_person_id,
      'guardian','active',now(),relation_row.created_by
    ) returning id into assignment_id;
  end if;

  insert into core.capability_grants(
    club_id,assignment_id,capability,scope_type,scope_id,starts_at,created_by
  ) values (
    relation_row.club_id,assignment_id,'team.roster.view','team',
    target_team_id,now(),relation_row.created_by
  ) on conflict(assignment_id,capability,scope_type,scope_id) do nothing;

  return assignment_id;
end;
$$;

create function internal.accept_guardian_invite_for_actor(
  raw_token text,
  idempotency_key uuid
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  actor_id uuid:=auth.uid();
  relation_id uuid;
begin
  if actor_id is null then
    raise insufficient_privilege using message='unauthenticated';
  end if;
  relation_id:=internal.accept_guardian_invite_and_link_for_actor(
    raw_token,idempotency_key
  );
  perform internal.ensure_guardian_context_for_relation(relation_id);
  return relation_id;
end;
$$;

revoke all on function internal.ensure_guardian_context_for_relation(uuid),
  internal.accept_guardian_invite_for_actor(text,uuid)
  from public,anon,authenticated;
grant execute on function internal.accept_guardian_invite_for_actor(text,uuid)
  to authenticated;

insert into internal.migration_provenance(
  migration_name,source_kind,source_reference
) values (
  '20260902091628_team05_guardian_relation_creates_context',
  'greenfield',
  'TEAM-05 guardian relation creates least-privilege team context'
);

notify pgrst,'reload schema';
