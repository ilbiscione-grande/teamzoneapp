-- TEAM-08: reactivate an archived roster person by creating a new history period.

create function internal.restore_archived_team_assignment_for_actor(
  target_club_id uuid,
  target_team_id uuid,
  target_club_person_id uuid,
  archived_assignment_id uuid,
  expected_revision bigint,
  reason text,
  idempotency_key uuid
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  actor_id uuid:=auth.uid();
  archived_row core.team_assignments%rowtype;
  new_assignment_id uuid;
  existing jsonb;
begin
  if actor_id is null then
    raise insufficient_privilege using message='unauthenticated';
  end if;

  select result into existing
  from internal.command_deduplication
  where actor_profile_id=actor_id
    and command_type='roster.assignment.restore.v1'
    and internal.command_deduplication.idempotency_key=
      restore_archived_team_assignment_for_actor.idempotency_key;
  if existing is not null then
    return (existing->>'assignment_id')::uuid;
  end if;

  if not internal.actor_has_capability(
    target_club_id,
    target_team_id,
    'club.memberships.manage'
  ) or length(btrim(coalesce(reason,''))) not between 2 and 240 then
    raise insufficient_privilege using message='not_found';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(target_club_id::text||':'||target_club_person_id::text,0)
  );
  select assignment.* into archived_row
  from core.team_assignments assignment
  join core.club_people person
    on person.id=assignment.club_person_id
   and person.club_id=assignment.club_id
  where assignment.id=archived_assignment_id
    and assignment.club_id=target_club_id
    and assignment.team_id=target_team_id
    and assignment.club_person_id=target_club_person_id
    and person.status='active'
    and person.provenance<>'anonymized'
  for update of assignment;

  if archived_row.id is null then
    raise insufficient_privilege using message='not_found';
  end if;
  if archived_row.revision<>expected_revision then
    raise serialization_failure using message='stale_revision';
  end if;
  if archived_row.state<>'ended' then
    raise check_violation using message='invalid_transition';
  end if;
  if exists(
    select 1 from core.team_assignments active_assignment
    where active_assignment.club_person_id=target_club_person_id
      and active_assignment.state='active'
  ) then
    raise check_violation using message='active_assignment_exists';
  end if;

  insert into core.team_assignments(
    club_id,
    team_id,
    club_person_id,
    starts_at,
    created_by
  ) values(
    target_club_id,
    target_team_id,
    target_club_person_id,
    now(),
    actor_id
  ) returning id into new_assignment_id;

  insert into internal.command_deduplication(
    actor_profile_id,
    idempotency_key,
    command_type,
    result
  ) values(
    actor_id,
    idempotency_key,
    'roster.assignment.restore.v1',
    jsonb_build_object('assignment_id',new_assignment_id)
  );
  insert into audit.command_events(
    club_id,
    actor_profile_id,
    command_type,
    aggregate_type,
    aggregate_id,
    aggregate_revision,
    reason,
    metadata
  ) values(
    target_club_id,
    actor_id,
    'roster.assignment.restore.v1',
    'team_assignment',
    new_assignment_id,
    1,
    btrim(reason),
    jsonb_build_object('archived_assignment_id',archived_row.id)
  );
  return new_assignment_id;
end
$$;

create or replace function internal.list_roster_lifecycle_for_actor(
  target_club_id uuid,
  target_team_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare result jsonb;
begin
  if auth.uid() is null or not internal.actor_has_capability(
    target_club_id,
    target_team_id,
    'club.memberships.manage'
  ) then
    raise insufficient_privilege using message='not_found';
  end if;
  select jsonb_build_object(
    'people',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'club_person_id',person.id,
          'person_name',person.display_name,
          'assignment_id',assignment.id,
          'assignment_state',assignment.state,
          'assignment_revision',assignment.revision,
          'can_reactivate',assignment.state='ended'
            and person.status='active'
            and person.provenance<>'anonymized'
            and not exists(
              select 1 from core.team_assignments active_assignment
              where active_assignment.club_person_id=person.id
                and active_assignment.state='active'
            )
        ) order by assignment.state='active' desc,person.display_name,person.id
      )
      from core.team_assignments assignment
      join core.club_people person
        on person.id=assignment.club_person_id
       and person.club_id=assignment.club_id
      where assignment.club_id=target_club_id
        and assignment.team_id=target_team_id
        and assignment.id=(
          select latest.id from core.team_assignments latest
          where latest.club_id=assignment.club_id
            and latest.team_id=assignment.team_id
            and latest.club_person_id=assignment.club_person_id
          order by latest.state='active' desc,latest.starts_at desc,latest.id desc
          limit 1
        )
    ),'[]'::jsonb),
    'requests',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'request_id',request.id,
          'club_person_id',request.club_person_id,
          'person_name',person.display_name,
          'state',request.state,
          'initiated_by',request.initiated_by,
          'revision',request.revision
        ) order by request.created_at desc
      )
      from core.club_person_erasure_requests request
      join core.club_people person on person.id=request.club_person_id
      where request.club_id=target_club_id
        and request.team_id=target_team_id
    ),'[]'::jsonb)
  ) into result;
  return result;
end
$$;

create function api.restore_archived_team_assignment(
  target_club_id uuid,
  target_team_id uuid,
  target_club_person_id uuid,
  archived_assignment_id uuid,
  expected_revision bigint,
  reason text,
  idempotency_key uuid
)
returns uuid
language sql
security invoker
set search_path=''
as $$
  select internal.restore_archived_team_assignment_for_actor(
    target_club_id,
    target_team_id,
    target_club_person_id,
    archived_assignment_id,
    expected_revision,
    reason,
    idempotency_key
  )
$$;

revoke all on function internal.restore_archived_team_assignment_for_actor(
  uuid,uuid,uuid,uuid,bigint,text,uuid
) from public,anon,authenticated;
revoke all on function api.restore_archived_team_assignment(
  uuid,uuid,uuid,uuid,bigint,text,uuid
) from public,anon,authenticated;

grant execute on function internal.restore_archived_team_assignment_for_actor(
  uuid,uuid,uuid,uuid,bigint,text,uuid
) to authenticated;
grant execute on function api.restore_archived_team_assignment(
  uuid,uuid,uuid,uuid,bigint,text,uuid
) to authenticated;

insert into internal.migration_provenance(
  migration_name,
  source_kind,
  source_reference
) values(
  '20260913131353_team08_restore_archived_assignment',
  'greenfield',
  'TEAM-08 archived roster filter and history-preserving reactivation'
);

notify pgrst,'reload schema';
