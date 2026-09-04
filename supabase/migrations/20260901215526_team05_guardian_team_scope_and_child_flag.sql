-- TEAM-05: make the guardian prerequisite manageable from the roster and
-- authorise invitation issue against the child's exact active team scope.

create function internal.set_guardian_requirement_for_actor(
  target_club_id uuid,
  target_team_id uuid,
  target_club_person_id uuid,
  guardian_required boolean,
  expected_revision bigint,
  idempotency_key uuid
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  person core.club_people%rowtype;
  existing_result jsonb;
  new_revision bigint;
begin
  if actor_id is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;
  if not internal.actor_has_capability(
    target_club_id,
    target_team_id,
    'club.memberships.manage'
  ) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  select result into existing_result
  from internal.command_deduplication
  where actor_profile_id = actor_id
    and command_type = 'roster.person.guardian_requirement.set.v1'
    and internal.command_deduplication.idempotency_key =
      set_guardian_requirement_for_actor.idempotency_key;
  if existing_result is not null then
    return (existing_result ->> 'revision')::bigint;
  end if;

  select * into person
  from core.club_people
  where id = target_club_person_id
    and club_id = target_club_id
    and status = 'active'
  for update;
  if person.id is null or not exists (
    select 1
    from core.team_assignments assignment
    where assignment.club_id = target_club_id
      and assignment.team_id = target_team_id
      and assignment.club_person_id = person.id
      and assignment.state = 'active'
      and assignment.starts_at <= now()
      and (assignment.ends_at is null or assignment.ends_at > now())
  ) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if person.revision <> expected_revision then
    raise serialization_failure using message = 'stale_revision';
  end if;

  update core.club_people
  set safeguarding_required = guardian_required,
      revision = revision + 1
  where id = person.id
  returning revision into new_revision;

  insert into internal.command_deduplication(
    actor_profile_id,idempotency_key,command_type,result
  ) values (
    actor_id,idempotency_key,'roster.person.guardian_requirement.set.v1',
    jsonb_build_object('revision',new_revision)
  );
  insert into audit.command_events(
    club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,
    aggregate_revision,metadata
  ) values (
    target_club_id,actor_id,'roster.person.guardian_requirement.set.v1',
    'club_person',person.id,new_revision,
    jsonb_build_object(
      'team_id',target_team_id,
      'guardian_required',guardian_required
    )
  );
  return new_revision;
end;
$$;

create or replace function internal.issue_guardian_invite_for_actor(
  target_guardian_person_id uuid,
  target_child_person_id uuid,
  raw_token text,
  expires_at timestamptz,
  idempotency_key uuid
)
returns uuid
language plpgsql
security definer
set search_path = '', extensions
as $$
declare
  actor_id uuid := auth.uid();
  target_club_id uuid;
  child_requires_guardian boolean;
  invite_id uuid;
  existing_result jsonb;
  actor_may_invite boolean := false;
begin
  if actor_id is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;
  select child.club_id,child.safeguarding_required
  into target_club_id,child_requires_guardian
  from core.club_people child
  where child.id = target_child_person_id and child.status = 'active';

  if target_club_id is not null and child_requires_guardian then
    actor_may_invite :=
      internal.actor_has_capability(
        target_club_id,null,'club.safeguarding.manage'
      ) or exists (
        select 1
        from core.team_assignments child_assignment
        where child_assignment.club_id = target_club_id
          and child_assignment.club_person_id = target_child_person_id
          and child_assignment.state = 'active'
          and child_assignment.starts_at <= now()
          and (child_assignment.ends_at is null or child_assignment.ends_at > now())
          and (
            internal.actor_has_capability(
              target_club_id,child_assignment.team_id,'club.safeguarding.manage'
            ) or internal.actor_has_capability(
              target_club_id,child_assignment.team_id,'club.memberships.manage'
            )
          )
      );
  end if;

  if target_club_id is null
     or not child_requires_guardian
     or not exists (
       select 1 from core.club_people guardian
       where guardian.id = target_guardian_person_id
         and guardian.club_id = target_club_id
         and guardian.status = 'active'
     )
     or not actor_may_invite then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if length(raw_token) < 32
     or expires_at <= now()
     or expires_at > now() + interval '7 days' then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  select result into existing_result
  from internal.command_deduplication
  where actor_profile_id = actor_id
    and command_type = 'roster.guardian_invite.issue.v1'
    and internal.command_deduplication.idempotency_key =
      issue_guardian_invite_for_actor.idempotency_key;
  if existing_result is not null then
    return (existing_result ->> 'invite_id')::uuid;
  end if;
  if exists (
    select 1 from core.guardian_relations relation
    where relation.guardian_person_id = target_guardian_person_id
      and relation.child_person_id = target_child_person_id
      and relation.state = 'active'
  ) then
    raise unique_violation using message = 'guardian_relation_conflict';
  end if;
  insert into core.guardian_invites(
    club_id,guardian_person_id,child_person_id,token_hash,expires_at,created_by
  ) values (
    target_club_id,target_guardian_person_id,target_child_person_id,
    extensions.digest(raw_token,'sha256'),expires_at,actor_id
  ) returning id into invite_id;
  insert into internal.command_deduplication(
    actor_profile_id,idempotency_key,command_type,result
  ) values (
    actor_id,idempotency_key,'roster.guardian_invite.issue.v1',
    jsonb_build_object('invite_id',invite_id)
  );
  insert into audit.command_events(
    club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,
    aggregate_revision
  ) values (
    target_club_id,actor_id,'roster.guardian_invite.issue.v1',
    'guardian_invite',invite_id,1
  );
  return invite_id;
end;
$$;

create function api.set_guardian_requirement(
  target_club_id uuid,
  target_team_id uuid,
  target_club_person_id uuid,
  guardian_required boolean,
  expected_revision bigint,
  idempotency_key uuid
)
returns bigint
language sql
security invoker
set search_path = ''
as $$
  select internal.set_guardian_requirement_for_actor(
    target_club_id,target_team_id,target_club_person_id,guardian_required,
    expected_revision,idempotency_key
  )
$$;

revoke all on function internal.set_guardian_requirement_for_actor(
  uuid,uuid,uuid,boolean,bigint,uuid
),api.set_guardian_requirement(uuid,uuid,uuid,boolean,bigint,uuid)
from public,anon,authenticated;
revoke all on function internal.issue_guardian_invite_for_actor(
  uuid,uuid,text,timestamptz,uuid
) from public,anon,authenticated;
grant execute on function internal.set_guardian_requirement_for_actor(
  uuid,uuid,uuid,boolean,bigint,uuid
),api.set_guardian_requirement(uuid,uuid,uuid,boolean,bigint,uuid)
to authenticated;
grant execute on function internal.issue_guardian_invite_for_actor(
  uuid,uuid,text,timestamptz,uuid
) to authenticated;

insert into internal.migration_provenance(
  migration_name,source_kind,source_reference
) values (
  '20260901215526_team05_guardian_team_scope_and_child_flag','greenfield',
  'TEAM-05 guardian prerequisite and team-scoped invitation'
);
notify pgrst,'reload schema';
