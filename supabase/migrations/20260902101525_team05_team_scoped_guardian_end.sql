-- Allow the same team-scoped managers who issue guardian invitations to end
-- the resulting relation, and remove the derived context when no relation
-- remains for that guardian in the team.

create or replace function internal.end_guardian_relation_for_actor(
  target_relation_id uuid,
  expected_revision bigint,
  idempotency_key uuid
)
returns bigint
language plpgsql
security definer
set search_path=''
as $$
declare
  actor_id uuid:=auth.uid();
  relation core.guardian_relations%rowtype;
  existing jsonb;
  new_revision bigint;
  target_team_id uuid;
  actor_is_guardian boolean;
begin
  if actor_id is null then
    raise insufficient_privilege using message='unauthenticated';
  end if;
  select result into existing
  from internal.command_deduplication
  where actor_profile_id=actor_id
    and command_type='roster.guardian_relation.end.v1'
    and internal.command_deduplication.idempotency_key=
      end_guardian_relation_for_actor.idempotency_key;
  if existing is not null then
    return(existing->>'revision')::bigint;
  end if;

  select * into relation
  from core.guardian_relations
  where id=target_relation_id
  for update;
  if relation.id is null then
    raise insufficient_privilege using message='not_found';
  end if;

  select assignment.team_id into target_team_id
  from core.team_assignments assignment
  where assignment.club_id=relation.club_id
    and assignment.club_person_id=relation.child_person_id
    and assignment.state='active'
    and assignment.starts_at<=now()
    and (assignment.ends_at is null or assignment.ends_at>now())
  order by assignment.starts_at desc,assignment.id desc
  limit 1;

  select exists(
    select 1 from core.person_account_links link
    where link.club_id=relation.club_id
      and link.club_person_id=relation.guardian_person_id
      and link.profile_id=actor_id
      and link.state='active'
  ) into actor_is_guardian;

  if not actor_is_guardian and (
    target_team_id is null or (
      not internal.actor_has_capability(
        relation.club_id,target_team_id,'club.safeguarding.manage'
      )
      and not internal.actor_has_capability(
        relation.club_id,target_team_id,'club.memberships.manage'
      )
      and not internal.actor_has_capability(
        relation.club_id,null,'club.safeguarding.manage'
      )
      and not internal.actor_has_capability(
        relation.club_id,null,'club.memberships.manage'
      )
    )
  ) then
    raise insufficient_privilege using message='not_found';
  end if;
  if relation.revision<>expected_revision then
    raise serialization_failure using message='stale_revision';
  end if;
  if relation.state<>'active' then
    raise check_violation using message='invalid_transition';
  end if;

  update core.guardian_relations
  set state='ended',
      ends_at=greatest(now(),starts_at+interval '1 microsecond'),
      revision=revision+1
  where id=relation.id
  returning revision into new_revision;

  if target_team_id is not null and not exists(
    select 1
    from core.guardian_relations other_relation
    join core.team_assignments child_assignment
      on child_assignment.club_id=other_relation.club_id
     and child_assignment.club_person_id=other_relation.child_person_id
     and child_assignment.team_id=target_team_id
     and child_assignment.state='active'
    where other_relation.id<>relation.id
      and other_relation.club_id=relation.club_id
      and other_relation.guardian_person_id=relation.guardian_person_id
      and other_relation.state='active'
      and other_relation.starts_at<=now()
      and (other_relation.ends_at is null or other_relation.ends_at>now())
  ) then
    update core.assignments
    set state='ended',
        ends_at=greatest(now(),starts_at+interval '1 microsecond'),
        revision=revision+1
    where club_id=relation.club_id
      and team_id=target_team_id
      and club_person_id=relation.guardian_person_id
      and role_package='guardian'
      and state='active';
  end if;

  insert into internal.command_deduplication(
    actor_profile_id,idempotency_key,command_type,result
  ) values (
    actor_id,idempotency_key,'roster.guardian_relation.end.v1',
    jsonb_build_object('revision',new_revision)
  );
  insert into audit.command_events(
    club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,
    aggregate_revision,metadata
  ) values (
    relation.club_id,actor_id,'roster.guardian_relation.end.v1',
    'guardian_relation',relation.id,new_revision,
    jsonb_build_object(
      'acting_as_guardian_person_id',
      case when actor_is_guardian then relation.guardian_person_id else null end,
      'child_person_id',relation.child_person_id,
      'team_id',target_team_id
    )
  );
  return new_revision;
end;
$$;

insert into internal.migration_provenance(
  migration_name,source_kind,source_reference
) values (
  '20260902101525_team05_team_scoped_guardian_end',
  'greenfield',
  'TEAM-05 team-scoped guardian end and derived-context cleanup'
);

notify pgrst,'reload schema';
