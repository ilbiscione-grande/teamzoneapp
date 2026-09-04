-- TEAM-05: keep shared team codes recoverable for authorised leaders while
-- preserving the hash-only claim path. The recoverable value lives in Vault.

alter table core.team_join_codes
  add column vault_secret_id uuid;

create or replace function internal.issue_team_join_code_for_actor(
  target_club_id uuid,
  target_team_id uuid,
  requested_role text,
  raw_token text,
  expires_at timestamptz,
  max_uses integer,
  idempotency_key uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  code_id uuid;
  secret_id uuid;
  existing jsonb;
begin
  if actor_id is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;
  if not internal.actor_has_capability(
       target_club_id,
       target_team_id,
       'club.memberships.manage'
     )
     or not exists (
       select 1
       from core.teams
       where id = target_team_id
         and club_id = target_club_id
         and status = 'active'
     ) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if requested_role not in ('player','leader','guardian','club_functionary')
     or length(raw_token) < 32
     or expires_at <= now()
     or expires_at > now() + interval '90 days'
     or max_uses not between 1 and 500 then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;

  select result
  into existing
  from internal.command_deduplication
  where actor_profile_id = actor_id
    and command_type = 'roster.team_code.issue.v1'
    and internal.command_deduplication.idempotency_key =
      issue_team_join_code_for_actor.idempotency_key;
  if existing is not null then
    return (existing ->> 'code_id')::uuid;
  end if;

  code_id := gen_random_uuid();
  select vault.create_secret(
    raw_token,
    'team_join_code_' || code_id::text,
    'Encrypted TeamZone team join code'
  ) into secret_id;

  insert into core.team_join_codes(
    id,
    club_id,
    team_id,
    token_hash,
    vault_secret_id,
    requested_role,
    expires_at,
    max_uses,
    created_by
  ) values (
    code_id,
    target_club_id,
    target_team_id,
    extensions.digest(raw_token, 'sha256'),
    secret_id,
    requested_role,
    expires_at,
    max_uses,
    actor_id
  );

  insert into internal.command_deduplication(
    actor_profile_id,
    idempotency_key,
    command_type,
    result
  ) values (
    actor_id,
    idempotency_key,
    'roster.team_code.issue.v1',
    jsonb_build_object('code_id', code_id)
  );
  insert into audit.command_events(
    club_id,
    actor_profile_id,
    command_type,
    aggregate_type,
    aggregate_id,
    aggregate_revision
  ) values (
    target_club_id,
    actor_id,
    'roster.team_code.issue.v1',
    'team_join_code',
    code_id,
    1
  );
  return code_id;
end;
$$;

create function internal.reveal_team_join_code_for_actor(target_code_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  code core.team_join_codes%rowtype;
  raw_token text;
begin
  if actor_id is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;
  select * into code
  from core.team_join_codes
  where id = target_code_id;
  if code.id is null
     or not internal.actor_has_capability(
       code.club_id,
       code.team_id,
       'club.memberships.manage'
     ) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if code.state <> 'issued'
     or code.expires_at <= now()
     or code.use_count >= code.max_uses then
    raise check_violation using message = 'code_not_active';
  end if;
  if code.vault_secret_id is null then
    raise check_violation using message = 'code_not_recoverable';
  end if;

  select decrypted_secret into raw_token
  from vault.decrypted_secrets
  where id = code.vault_secret_id;
  if raw_token is null then
    raise check_violation using message = 'code_not_recoverable';
  end if;

  insert into audit.command_events(
    club_id,
    actor_profile_id,
    command_type,
    aggregate_type,
    aggregate_id,
    aggregate_revision,
    metadata
  ) values (
    code.club_id,
    actor_id,
    'roster.team_code.reveal.v1',
    'team_join_code',
    code.id,
    code.revision,
    jsonb_build_object('team_id', code.team_id)
  );
  return raw_token;
end;
$$;

create function api.reveal_team_join_code(code_id uuid)
returns text
language sql
security invoker
set search_path = ''
as $$
  select internal.reveal_team_join_code_for_actor(code_id)
$$;

revoke all on function internal.issue_team_join_code_for_actor(
  uuid,uuid,text,text,timestamptz,integer,uuid
) from public,anon,authenticated;
revoke all on function internal.reveal_team_join_code_for_actor(uuid),
  api.reveal_team_join_code(uuid) from public,anon,authenticated;
grant execute on function internal.issue_team_join_code_for_actor(
  uuid,uuid,text,text,timestamptz,integer,uuid
) to authenticated;
grant execute on function internal.reveal_team_join_code_for_actor(uuid),
  api.reveal_team_join_code(uuid) to authenticated;

insert into internal.migration_provenance(
  migration_name,
  source_kind,
  source_reference
) values (
  '20260901211827_team05_reveal_encrypted_team_code',
  'greenfield',
  'TEAM-05 encrypted and audited team-code reveal'
);

notify pgrst, 'reload schema';
