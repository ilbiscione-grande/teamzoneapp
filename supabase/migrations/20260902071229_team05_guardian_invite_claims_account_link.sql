-- A guardian invitation is the proof used to bind a previously unlinked
-- account to the intended guardian person. Existing conflicting links remain
-- fail-closed.

create or replace function internal.accept_guardian_invite_for_actor(
  raw_token text,
  idempotency_key uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  invite_row core.guardian_invites%rowtype;
  relation_id uuid;
  linked_profile_id uuid;
  existing_result jsonb;
begin
  if actor_id is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;

  select result into existing_result
  from internal.command_deduplication
  where actor_profile_id = actor_id
    and command_type = 'roster.guardian_invite.accept.v1'
    and internal.command_deduplication.idempotency_key =
      accept_guardian_invite_for_actor.idempotency_key;
  if existing_result is not null then
    return (existing_result ->> 'guardian_relation_id')::uuid;
  end if;

  select * into invite_row
  from core.guardian_invites
  where token_hash = extensions.digest(raw_token, 'sha256')
  for update;

  if invite_row.id is null
     or invite_row.state <> 'issued'
     or invite_row.expires_at <= now() then
    raise invalid_parameter_value using message = 'invalid_or_expired_token';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(invite_row.club_id::text || ':' ||
      invite_row.guardian_person_id::text, 0)
  );

  select link.profile_id into linked_profile_id
  from core.person_account_links link
  where link.club_id = invite_row.club_id
    and link.club_person_id = invite_row.guardian_person_id
    and link.state = 'active'
  limit 1;

  if linked_profile_id is not null and linked_profile_id <> actor_id then
    raise insufficient_privilege using message = 'guardian_person_already_linked';
  end if;

  if linked_profile_id is null then
    if exists (
      select 1
      from core.person_account_links link
      where link.club_id = invite_row.club_id
        and link.profile_id = actor_id
        and link.club_person_id <> invite_row.guardian_person_id
        and link.state = 'active'
    ) then
      raise insufficient_privilege using message = 'guardian_account_conflict';
    end if;

    insert into core.person_account_links(
      club_id,
      club_person_id,
      profile_id,
      state,
      verified_at,
      created_by
    ) values (
      invite_row.club_id,
      invite_row.guardian_person_id,
      actor_id,
      'active',
      now(),
      actor_id
    );
  end if;

  insert into core.guardian_relations(
    club_id,
    guardian_person_id,
    child_person_id,
    kind,
    state,
    starts_at,
    created_by
  ) values (
    invite_row.club_id,
    invite_row.guardian_person_id,
    invite_row.child_person_id,
    'guardian',
    'active',
    now(),
    actor_id
  ) returning id into relation_id;

  update core.guardian_invites
  set state = 'consumed',
      consumed_at = now(),
      consumed_by = actor_id,
      revision = revision + 1
  where id = invite_row.id;

  insert into internal.command_deduplication(
    actor_profile_id,
    idempotency_key,
    command_type,
    result
  ) values (
    actor_id,
    idempotency_key,
    'roster.guardian_invite.accept.v1',
    jsonb_build_object('guardian_relation_id', relation_id)
  );

  insert into audit.command_events(
    club_id,
    actor_profile_id,
    command_type,
    aggregate_type,
    aggregate_id,
    aggregate_revision,
    metadata
  ) values (
    invite_row.club_id,
    actor_id,
    'roster.guardian_invite.accept.v1',
    'guardian_relation',
    relation_id,
    1,
    jsonb_build_object(
      'acting_as_guardian_person_id', invite_row.guardian_person_id,
      'child_person_id', invite_row.child_person_id,
      'account_link_created', linked_profile_id is null
    )
  );

  return relation_id;
end;
$$;

insert into internal.migration_provenance(
  migration_name,
  source_kind,
  source_reference
) values (
  '20260902071229_team05_guardian_invite_claims_account_link',
  'greenfield',
  'TEAM-05 invitation-bound guardian account claim with conflict protection'
);

notify pgrst, 'reload schema';
