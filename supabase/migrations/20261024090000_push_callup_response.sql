-- Answer a callup from its notification (decided 2026-10-13): callups first,
-- "Kommer" answers from the notification, "Kan inte…" opens the app (a
-- decline needs a reason), and Android asks for unlock before answering.
--
-- * The push for a callup that waits for an answer carries a single-use
--   response token. Only its SHA-256 hash is stored; it expires with the
--   callup (at most 14 days) and answers "accepted" for that one callup and
--   person only.
-- * push-callup-response (Edge Function, no user session: the action runs in
--   the background) passes the token to internal.respond_callup_from_push,
--   which answers as the notification's recipient through
--   internal.respond_callup_for_actor, so the rules (own callup, guardian,
--   state, expiry) are the same as in the app. Service role only.

create table if not exists internal.push_response_tokens (
  id uuid primary key default gen_random_uuid(),
  callup_id uuid not null references core.callups(id) on delete cascade,
  recipient_profile_id uuid not null,
  acting_as_person_id uuid,
  token_hash bytea not null unique,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);
alter table internal.push_response_tokens enable row level security;
revoke all on internal.push_response_tokens from public, anon, authenticated;

-- As in 20261023090000, plus the response token for an open callup and the
-- recipient's language (for the buttons; the function now writes, so it is
-- no longer stable).
create or replace function internal.push_message_for_outbox(target_outbox_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare outbox internal.notification_outbox%rowtype; profile core.profiles%rowtype;
  swedish boolean; event_row core.events%rowtype; team_name text; kind text;
  title text; body text; callup_row core.callups%rowtype; raw_token text;
  response jsonb;
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
    if outbox.event_type ~ '^callup\.callup\.(sent|late_sent|reminded)\.'
      and outbox.payload_ref->>'callup_id' ~ '^[0-9a-fA-F-]{36}$' then
      select * into callup_row from core.callups where id = (outbox.payload_ref->>'callup_id')::uuid;
      if callup_row.id is not null and callup_row.event_id = event_row.id and callup_row.state = 'pending'
        and (callup_row.expires_at is null or callup_row.expires_at > now()) then
        delete from internal.push_response_tokens
        where expires_at <= now() or consumed_at < now() - interval '1 day';
        raw_token := encode(extensions.gen_random_bytes(32), 'hex');
        insert into internal.push_response_tokens(callup_id, recipient_profile_id, acting_as_person_id,
          token_hash, expires_at)
        values (callup_row.id, outbox.recipient_profile_id,
          -- A guardian answers for the called child.
          case when outbox.recipient_person_id is distinct from callup_row.club_person_id
            then callup_row.club_person_id end,
          extensions.digest(raw_token, 'sha256'),
          least(callup_row.expires_at, now() + interval '14 days'));
        response := jsonb_build_object('callup_id', callup_row.id, 'token', raw_token);
      end if;
    end if;
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
    'response', response,
    'language', case when swedish then 'sv' else 'en' end,
    'targets', coalesce((
      select jsonb_agg(jsonb_build_object('endpoint_id', endpoint.id, 'platform', stored.platform,
        'token', extensions.pgp_sym_decrypt(stored.token_ciphertext, internal.push_token_key())))
      from core.notification_endpoints endpoint
      join internal.push_endpoint_tokens stored on stored.endpoint_id = endpoint.id
      where endpoint.profile_id = outbox.recipient_profile_id and endpoint.channel = 'push'
        and endpoint.state = 'active'), '[]'::jsonb));
end;$$;

-- "Kommer" from a notification. A repeated tap (or a retry after a lost
-- reply) gets the same answer; an expired, unknown or no longer answerable
-- callup raises, and the app then opens the event instead.
create or replace function internal.respond_callup_from_push(raw_token text, idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare token_row internal.push_response_tokens%rowtype; callup_row core.callups%rowtype;
  previous_sub text; previous_claims text; result_revision bigint;
begin
  if current_user not in ('postgres', 'service_role') then raise insufficient_privilege; end if;
  if raw_token is null or raw_token !~ '^[0-9a-f]{64}$' or idempotency_key is null then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  select * into token_row from internal.push_response_tokens
  where token_hash = extensions.digest(raw_token, 'sha256') for update;
  if token_row.id is null or token_row.expires_at <= now() then
    raise insufficient_privilege using message = 'invalid_or_expired_token';
  end if;
  if token_row.consumed_at is not null then
    return jsonb_build_object('response', 'accepted', 'repeated', true);
  end if;
  select * into callup_row from core.callups where id = token_row.callup_id;
  -- Answer as the recipient, with the app's own rules; the claims are
  -- transaction-local and restored afterwards.
  previous_sub := current_setting('request.jwt.claim.sub', true);
  previous_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claim.sub', token_row.recipient_profile_id::text, true);
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', token_row.recipient_profile_id, 'role', 'authenticated')::text, true);
  result_revision := internal.respond_callup_for_actor(callup_row.id, 'accepted',
    token_row.acting_as_person_id, null, null, callup_row.revision, idempotency_key);
  perform set_config('request.jwt.claim.sub', coalesce(previous_sub, ''), true);
  perform set_config('request.jwt.claims', coalesce(previous_claims, ''), true);
  update internal.push_response_tokens set consumed_at = now() where id = token_row.id;
  return jsonb_build_object('response', 'accepted', 'revision', result_revision);
end;$$;

create or replace function api.respond_callup_from_push(raw_token text, idempotency_key uuid)
returns jsonb language sql security invoker set search_path = '' as
$$select internal.respond_callup_from_push(raw_token, idempotency_key)$$;

revoke all on function internal.respond_callup_from_push(text, uuid),
  api.respond_callup_from_push(text, uuid) from public, anon, authenticated;
grant execute on function internal.respond_callup_from_push(text, uuid),
  api.respond_callup_from_push(text, uuid) to service_role;

insert into internal.migration_provenance (migration_name, source_kind, source_reference)
select '20261024090000_push_callup_response', 'greenfield',
  'Answer a callup from its notification: single-use response token, service-role response'
where not exists (select 1 from internal.migration_provenance where migration_name = '20261024090000_push_callup_response');
notify pgrst, 'reload schema';
