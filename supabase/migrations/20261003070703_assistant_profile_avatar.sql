alter table core.assistant_preferences
  add column avatar_key text,
  add constraint assistant_preferences_avatar_key_check
    check (avatar_key is null or avatar_key in ('woman','man'));

create or replace function internal.get_assistant_preference_for_actor()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'custom_name', preference.custom_name,
    'avatar_key', preference.avatar_key,
    'revision', coalesce(preference.revision, 0)
  )
  from (select auth.uid() as profile_id) actor
  left join core.assistant_preferences preference
    on preference.profile_id = actor.profile_id
  where actor.profile_id is not null;
$$;

create function internal.set_assistant_avatar_for_actor(
  avatar_key text,
  expected_revision bigint,
  idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  normalized_key text := nullif(btrim(avatar_key), '');
  preference core.assistant_preferences;
  next_revision bigint;
  existing_result jsonb;
begin
  if actor_id is null then raise exception 'unauthenticated'; end if;
  if idempotency_key is null then raise exception 'idempotency_key_required'; end if;
  if normalized_key is not null and normalized_key not in ('woman','man')
  then raise exception 'invalid_assistant_avatar'; end if;

  select dedupe.result into existing_result
  from internal.command_deduplication dedupe
  where dedupe.actor_profile_id = actor_id
    and dedupe.idempotency_key = set_assistant_avatar_for_actor.idempotency_key
    and dedupe.command_type = 'assistant.avatar.updated.v1';
  if existing_result is not null then return existing_result; end if;

  select * into preference
  from core.assistant_preferences current_preference
  where current_preference.profile_id = actor_id
  for update;
  if coalesce(preference.revision, 0) <> expected_revision
  then raise exception 'stale_revision'; end if;
  next_revision := coalesce(preference.revision, 0) + 1;

  insert into core.assistant_preferences(
    profile_id, custom_name, avatar_key, revision, updated_at
  ) values(actor_id, null, normalized_key, next_revision, now())
  on conflict(profile_id) do update set
    avatar_key = excluded.avatar_key,
    revision = excluded.revision,
    updated_at = excluded.updated_at;

  existing_result := jsonb_build_object(
    'custom_name', preference.custom_name,
    'avatar_key', normalized_key,
    'revision', next_revision
  );
  insert into internal.command_deduplication(
    actor_profile_id, idempotency_key, command_type, result
  ) values(
    actor_id, idempotency_key, 'assistant.avatar.updated.v1', existing_result
  );
  return existing_result;
end;
$$;

create function api.set_assistant_avatar(
  avatar_key text,
  expected_revision bigint,
  idempotency_key uuid
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select internal.set_assistant_avatar_for_actor(
    avatar_key, expected_revision, idempotency_key
  )
$$;

revoke all on function
  internal.set_assistant_avatar_for_actor(text,bigint,uuid),
  api.set_assistant_avatar(text,bigint,uuid)
from public, anon, authenticated;
grant execute on function
  internal.set_assistant_avatar_for_actor(text,bigint,uuid),
  api.set_assistant_avatar(text,bigint,uuid)
to authenticated;

insert into internal.migration_provenance(
  migration_name, source_kind, source_reference
) values(
  '20261003070703_assistant_profile_avatar',
  'greenfield',
  'Account-private assistant avatar choice from bundled TeamZone assets'
);

notify pgrst, 'reload schema';
