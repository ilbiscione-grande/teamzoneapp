-- Push delivery through Firebase Cloud Messaging (decided 2026-10-13).
--
-- * The app registers its FCM token after the user has allowed
--   notifications. core.notification_endpoints keeps the token's hash (as
--   before); the token itself is stored encrypted (pgcrypto, key in Vault) in
--   internal.push_endpoint_tokens and is readable only by the worker.
-- * A token moves with the device: registering it for one account disables
--   it for any other account, so a shared phone never shows the previous
--   user's notifications.
-- * Lock-screen text is "type + activity" without names or free text: the
--   event type, team and time for callups, the team for messages. Event
--   titles, thread titles and message bodies are never used.
-- * notification-worker is started every minute by pg_cron with its own
--   token (Vault `notification_worker_token`, Edge secret
--   NOTIFICATION_WORKER_TOKEN). Nothing is sent until the Edge secrets
--   FCM_SERVICE_ACCOUNT_JSON and NOTIFICATION_PUSH_ENABLED=true exist.

create extension if not exists pg_cron;
create extension if not exists pg_net;

create table if not exists internal.push_endpoint_tokens (
  endpoint_id uuid primary key references core.notification_endpoints(id) on delete cascade,
  platform text not null check (platform in ('android', 'ios')),
  token_ciphertext bytea not null,
  last_seen_at timestamptz not null default now()
);
alter table internal.push_endpoint_tokens enable row level security;
revoke all on internal.push_endpoint_tokens from public, anon, authenticated;

do $$
begin
  if not exists (select 1 from vault.secrets where name = 'push_token_key') then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'push_token_key',
      'Encrypts FCM device tokens in internal.push_endpoint_tokens');
  end if;
end $$;

create or replace function internal.push_token_key()
returns text language sql stable security definer set search_path = '' as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'push_token_key' limit 1
$$;

-- The signed-in user's device token.
create or replace function internal.register_push_endpoint_for_actor(platform text, token text)
returns void language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); token_hash bytea; endpoint uuid;
begin
  if actor_id is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  if platform is null or platform not in ('android', 'ios') or token is null
    or length(token) not between 20 and 4096 or token !~ '^[A-Za-z0-9:_.\-]+$'
  then raise invalid_parameter_value using message = 'invalid_push_token'; end if;
  token_hash := extensions.digest(token, 'sha256');
  -- The device now belongs to this account.
  delete from internal.push_endpoint_tokens stored using core.notification_endpoints other
  where stored.endpoint_id = other.id and other.channel = 'push'
    and other.endpoint_hash = token_hash and other.profile_id <> actor_id;
  update core.notification_endpoints set state = 'disabled'
  where channel = 'push' and endpoint_hash = token_hash and profile_id <> actor_id and state = 'active';
  insert into core.notification_endpoints (profile_id, channel, endpoint_hash, state)
  values (actor_id, 'push', token_hash, 'active')
  on conflict (profile_id, channel, endpoint_hash) do update set state = 'active'
  returning id into endpoint;
  insert into internal.push_endpoint_tokens (endpoint_id, platform, token_ciphertext, last_seen_at)
  values (endpoint, platform, extensions.pgp_sym_encrypt(token, internal.push_token_key()), now())
  on conflict (endpoint_id) do update set platform = excluded.platform,
    token_ciphertext = excluded.token_ciphertext, last_seen_at = now();
end;$$;

-- Signing out stops this device's notifications for the account.
create or replace function internal.unregister_push_endpoint_for_actor(token text)
returns void language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); token_hash bytea;
begin
  if actor_id is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  if token is null or length(token) > 4096 then raise invalid_parameter_value using message = 'invalid_push_token'; end if;
  token_hash := extensions.digest(token, 'sha256');
  delete from internal.push_endpoint_tokens stored using core.notification_endpoints own
  where stored.endpoint_id = own.id and own.profile_id = actor_id
    and own.channel = 'push' and own.endpoint_hash = token_hash;
  update core.notification_endpoints set state = 'disabled'
  where profile_id = actor_id and channel = 'push' and endpoint_hash = token_hash;
end;$$;

create or replace function internal.push_local_time(at timestamptz, zone text, swedish boolean)
returns text language sql stable set search_path = '' as $$
  select case when swedish
    then (array['sön','mån','tis','ons','tor','fre','lör'])[extract(dow from local)::int + 1]
      || ' ' || extract(day from local)::int || ' '
      || (array['jan','feb','mar','apr','maj','jun','jul','aug','sep','okt','nov','dec'])[extract(month from local)::int]
    else (array['Sun','Mon','Tue','Wed','Thu','Fri','Sat'])[extract(dow from local)::int + 1]
      || ' ' || extract(day from local)::int || ' '
      || (array['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'])[extract(month from local)::int]
    end || ' ' || to_char(local, 'HH24:MI')
  from (select at at time zone coalesce(nullif(zone, ''), 'Europe/Stockholm') as local) t
$$;

-- What the worker sends for one outbox row: lock-screen text, the in-app
-- route and the recipient's active device tokens. Service role only.
create or replace function internal.push_message_for_outbox(target_outbox_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare outbox internal.notification_outbox%rowtype; profile core.profiles%rowtype;
  swedish boolean; event_row core.events%rowtype; team_name text; kind text;
  title text; body text;
begin
  if current_user not in ('postgres', 'service_role') then raise insufficient_privilege; end if;
  select * into outbox from internal.notification_outbox where id = target_outbox_id;
  if outbox.id is null or outbox.recipient_profile_id is null then return null; end if;
  select * into profile from core.profiles where id = outbox.recipient_profile_id;
  swedish := coalesce(profile.locale, 'sv') not like 'en%';
  if outbox.event_type like 'callup.%' and outbox.payload_ref->>'event_id' ~ '^[0-9a-fA-F-]{36}$' then
    select * into event_row from core.events where id = (outbox.payload_ref->>'event_id')::uuid;
    if event_row.id is null then return null; end if;
    select name into team_name from core.teams where id = event_row.owning_team_id;
    kind := case event_row.event_type
      when 'training' then case when swedish then 'Träning' else 'Training' end
      when 'match' then 'Match'
      when 'meeting' then case when swedish then 'Möte' else 'Meeting' end
      else case when swedish then 'Aktivitet' else 'Activity' end end;
    title := case
      when outbox.event_type like 'callup.callup.cancelled.%' then case when swedish then 'Kallelsen är inställd' else 'Callup cancelled' end
      when outbox.event_type like 'callup.callup.reminded.%' then case when swedish then 'Påminnelse: svara på kallelsen' else 'Reminder: answer the callup' end
      else case when swedish then 'Ny kallelse' else 'New callup' end end;
    body := concat_ws(' · ', kind, team_name,
      internal.push_local_time(event_row.starts_at, coalesce(profile.timezone, event_row.timezone), swedish));
  elsif outbox.event_type = 'message.message.sent.v1' then
    select team.name into team_name from core.thread_scopes scope join core.teams team on team.id = scope.team_id
    where outbox.payload_ref->>'thread_id' ~ '^[0-9a-fA-F-]{36}$'
      and scope.thread_id = (outbox.payload_ref->>'thread_id')::uuid
    order by team.name limit 1;
    title := case when swedish then 'Nytt meddelande' else 'New message' end;
    body := coalesce(team_name, case when swedish then 'Öppna TeamZone för att läsa.' else 'Open TeamZone to read it.' end);
  else
    return null;
  end if;
  return jsonb_build_object(
    'title', title,
    'body', body,
    'route', internal.notification_deep_link(outbox),
    'targets', coalesce((
      select jsonb_agg(jsonb_build_object('endpoint_id', endpoint.id, 'platform', stored.platform,
        'token', extensions.pgp_sym_decrypt(stored.token_ciphertext, internal.push_token_key())))
      from core.notification_endpoints endpoint
      join internal.push_endpoint_tokens stored on stored.endpoint_id = endpoint.id
      where endpoint.profile_id = outbox.recipient_profile_id and endpoint.channel = 'push'
        and endpoint.state = 'active'), '[]'::jsonb));
end;$$;

-- FCM said the token is gone (app uninstalled, token rotated).
create or replace function internal.disable_push_endpoint(target_endpoint_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if current_user not in ('postgres', 'service_role') then raise insufficient_privilege; end if;
  delete from internal.push_endpoint_tokens where endpoint_id = target_endpoint_id;
  update core.notification_endpoints set state = 'disabled' where id = target_endpoint_id;
end;$$;

create or replace function api.register_push_endpoint(platform text, token text)
returns void language sql security invoker set search_path = '' as
$$select internal.register_push_endpoint_for_actor(platform, token)$$;
create or replace function api.unregister_push_endpoint(token text)
returns void language sql security invoker set search_path = '' as
$$select internal.unregister_push_endpoint_for_actor(token)$$;
create or replace function api.push_message_for_outbox(target_outbox_id uuid)
returns jsonb language sql security invoker set search_path = '' as
$$select internal.push_message_for_outbox(target_outbox_id)$$;
create or replace function api.disable_push_endpoint(target_endpoint_id uuid)
returns void language sql security invoker set search_path = '' as
$$select internal.disable_push_endpoint(target_endpoint_id)$$;

-- Minute schedule, like the support e-mail worker.
create or replace function internal.invoke_notification_worker()
returns bigint language plpgsql security definer set search_path = '' as $$
declare project_url text; worker_token text; request_id bigint;
begin
  select decrypted_secret into project_url from vault.decrypted_secrets where name = 'project_url' limit 1;
  select decrypted_secret into worker_token from vault.decrypted_secrets where name = 'notification_worker_token' limit 1;
  if nullif(project_url, '') is null or nullif(worker_token, '') is null then
    raise warning 'Notification worker skipped: Vault secret notification_worker_token is not configured';
    return null;
  end if;
  select net.http_post(
    url := rtrim(project_url, '/') || '/functions/v1/notification-worker',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-teamzone-worker-token', worker_token),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000)
  into request_id;
  return request_id;
end;$$;

revoke all on function internal.push_token_key(), internal.register_push_endpoint_for_actor(text, text),
  internal.unregister_push_endpoint_for_actor(text), internal.push_local_time(timestamptz, text, boolean),
  internal.push_message_for_outbox(uuid), internal.disable_push_endpoint(uuid),
  internal.invoke_notification_worker(),
  api.register_push_endpoint(text, text), api.unregister_push_endpoint(text),
  api.push_message_for_outbox(uuid), api.disable_push_endpoint(uuid)
  from public, anon, authenticated;
grant execute on function internal.register_push_endpoint_for_actor(text, text),
  internal.unregister_push_endpoint_for_actor(text),
  api.register_push_endpoint(text, text), api.unregister_push_endpoint(text) to authenticated;
grant execute on function internal.push_message_for_outbox(uuid), internal.disable_push_endpoint(uuid),
  internal.push_local_time(timestamptz, text, boolean),
  api.push_message_for_outbox(uuid), api.disable_push_endpoint(uuid) to service_role;

do $$
declare existing_job_id bigint;
begin
  select jobid into existing_job_id from cron.job where jobname = 'notification-worker' limit 1;
  if existing_job_id is not null then perform cron.unschedule(existing_job_id); end if;
end $$;
select cron.schedule('notification-worker', '* * * * *',
  $cron$ select internal.invoke_notification_worker(); $cron$);

insert into internal.migration_provenance (migration_name, source_kind, source_reference)
select '20261023090000_push_delivery', 'greenfield',
  'FCM push delivery: encrypted device tokens, type+activity lock-screen text, minute worker'
where not exists (select 1 from internal.migration_provenance where migration_name = '20261023090000_push_delivery');
notify pgrst, 'reload schema';
