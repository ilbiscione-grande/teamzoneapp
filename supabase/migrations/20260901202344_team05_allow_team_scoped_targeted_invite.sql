-- TEAM-05: targeted invitations may be issued by a leader for a person who
-- currently belongs to a team covered by the leader's roster permission.
-- Club-scoped administrators retain their existing access.

create or replace function internal.issue_roster_invite_for_actor(
  target_club_person_id uuid,
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
  invite_id uuid;
  existing_result jsonb;
  actor_may_invite boolean := false;
begin
  if actor_id is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;

  select club_id
  into target_club_id
  from core.club_people
  where id = target_club_person_id
    and status = 'active';

  if target_club_id is not null then
    actor_may_invite :=
      internal.actor_has_capability(
        target_club_id,
        null,
        'club.memberships.manage'
      )
      or exists (
        select 1
        from core.team_assignments target_assignment
        where target_assignment.club_id = target_club_id
          and target_assignment.club_person_id = target_club_person_id
          and target_assignment.state = 'active'
          and target_assignment.starts_at <= now()
          and (target_assignment.ends_at is null or target_assignment.ends_at > now())
          and (
            internal.actor_has_capability(
              target_club_id,
              target_assignment.team_id,
              'team.roster.manage'
            )
            or internal.actor_has_capability(
              target_club_id,
              target_assignment.team_id,
              'club.memberships.manage'
            )
          )
      );
  end if;

  if target_club_id is null or not actor_may_invite then
    raise insufficient_privilege using message = 'not_found';
  end if;

  if length(raw_token) < 32
     or expires_at <= now()
     or expires_at > now() + interval '14 days' then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;

  select result
  into existing_result
  from internal.command_deduplication
  where actor_profile_id = actor_id
    and command_type = 'roster.invite.issue.v1'
    and internal.command_deduplication.idempotency_key =
      issue_roster_invite_for_actor.idempotency_key;

  if existing_result is not null then
    return (existing_result ->> 'invite_id')::uuid;
  end if;

  insert into core.roster_invites(
    club_id,
    club_person_id,
    token_hash,
    expires_at,
    created_by
  )
  values (
    target_club_id,
    target_club_person_id,
    extensions.digest(raw_token, 'sha256'),
    expires_at,
    actor_id
  )
  returning id into invite_id;

  insert into internal.command_deduplication(
    actor_profile_id,
    idempotency_key,
    command_type,
    result
  )
  values (
    actor_id,
    idempotency_key,
    'roster.invite.issue.v1',
    jsonb_build_object('invite_id', invite_id)
  );

  insert into audit.command_events(
    club_id,
    actor_profile_id,
    command_type,
    aggregate_type,
    aggregate_id,
    aggregate_revision
  )
  values (
    target_club_id,
    actor_id,
    'roster.invite.issue.v1',
    'roster_invite',
    invite_id,
    1
  );

  return invite_id;
end;
$$;

revoke all on function internal.issue_roster_invite_for_actor(
  uuid,
  text,
  timestamptz,
  uuid
) from public, anon;

grant execute on function internal.issue_roster_invite_for_actor(
  uuid,
  text,
  timestamptz,
  uuid
) to authenticated;

insert into internal.migration_provenance(
  migration_name,
  source_kind,
  source_reference
)
values (
  '20260901202344_team05_allow_team_scoped_targeted_invite',
  'greenfield',
  'TEAM-05 team-scoped targeted invitation authorization'
);

notify pgrst, 'reload schema';
