create table core.assistant_preferences (
  profile_id uuid primary key references core.profiles(id) on delete cascade,
  custom_name text,
  revision bigint not null default 1 check (revision > 0),
  updated_at timestamptz not null default now(),
  constraint assistant_preferences_custom_name_check check (
    custom_name is null or (
      custom_name = btrim(custom_name)
      and char_length(custom_name) between 1 and 40
      and custom_name !~ '[[:cntrl:]]'
    )
  )
);

alter table core.assistant_preferences enable row level security;

create function internal.get_assistant_preference_for_actor()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'custom_name', preference.custom_name,
    'revision', coalesce(preference.revision, 0)
  )
  from (select auth.uid() as profile_id) actor
  left join core.assistant_preferences preference
    on preference.profile_id = actor.profile_id
  where actor.profile_id is not null;
$$;

create function internal.set_assistant_name_for_actor(
  custom_name text,
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
  normalized_name text := nullif(btrim(custom_name), '');
  current_revision bigint;
  next_revision bigint;
  existing_result jsonb;
begin
  if actor_id is null then raise exception 'unauthenticated'; end if;
  if idempotency_key is null then raise exception 'idempotency_key_required'; end if;
  if normalized_name is not null and (
    char_length(normalized_name) > 40 or normalized_name ~ '[[:cntrl:]]'
  ) then raise exception 'invalid_assistant_name'; end if;

  select dedupe.result into existing_result
  from internal.command_deduplication dedupe
  where dedupe.actor_profile_id = actor_id
    and dedupe.idempotency_key = set_assistant_name_for_actor.idempotency_key
    and dedupe.command_type = 'assistant.identity.updated.v1';
  if existing_result is not null then return existing_result; end if;

  select preference.revision into current_revision
  from core.assistant_preferences preference
  where preference.profile_id = actor_id
  for update;
  current_revision := coalesce(current_revision, 0);
  if current_revision <> expected_revision then
    raise exception 'stale_revision';
  end if;
  next_revision := current_revision + 1;

  insert into core.assistant_preferences(
    profile_id, custom_name, revision, updated_at
  ) values(actor_id, normalized_name, next_revision, now())
  on conflict(profile_id) do update set
    custom_name = excluded.custom_name,
    revision = excluded.revision,
    updated_at = excluded.updated_at;

  existing_result := jsonb_build_object(
    'custom_name', normalized_name,
    'revision', next_revision
  );
  insert into internal.command_deduplication(
    actor_profile_id, idempotency_key, command_type, result
  ) values(
    actor_id, idempotency_key, 'assistant.identity.updated.v1', existing_result
  );
  return existing_result;
end;
$$;

create function api.get_assistant_preference()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$select internal.get_assistant_preference_for_actor()$$;

create function api.set_assistant_name(
  custom_name text,
  expected_revision bigint,
  idempotency_key uuid
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select internal.set_assistant_name_for_actor(
    custom_name, expected_revision, idempotency_key
  )
$$;

revoke all on table core.assistant_preferences from public, anon, authenticated;
revoke all on function internal.get_assistant_preference_for_actor(),
  internal.set_assistant_name_for_actor(text,bigint,uuid),
  api.get_assistant_preference(),
  api.set_assistant_name(text,bigint,uuid)
from public, anon, authenticated;
grant execute on function internal.get_assistant_preference_for_actor(),
  internal.set_assistant_name_for_actor(text,bigint,uuid),
  api.get_assistant_preference(),
  api.set_assistant_name(text,bigint,uuid)
to authenticated;

insert into internal.migration_provenance(
  migration_name, source_kind, source_reference
) values(
  '20260828160052_ac04_assistant_identity_preferences',
  'greenfield',
  'AC-04 private account-synced assistant identity preference'
);
