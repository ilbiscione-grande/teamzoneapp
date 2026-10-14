-- Reply to a message from its notification (Android), like answering a
-- callup (20261024090000): the push for a message in a thread one can write
-- in carries a single-use reply token (only its SHA-256 hash is stored; 7
-- days, one reply, that thread only). "Svara" takes the text in the
-- notification after unlock; push-message-reply passes it to
-- internal.reply_from_push, which sends it as the recipient through
-- internal.send_message_for_actor, so the app's rules apply (access, length,
-- closed announcements). Lock screens never show message text.

create table if not exists internal.push_reply_tokens (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references core.message_threads(id) on delete cascade,
  recipient_profile_id uuid not null,
  token_hash bytea not null unique,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);
alter table internal.push_reply_tokens enable row level security;
revoke all on internal.push_reply_tokens from public, anon, authenticated;

-- As in 20261024090000, plus the reply token for a message.
create or replace function internal.push_message_for_outbox(target_outbox_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare outbox internal.notification_outbox%rowtype; profile core.profiles%rowtype;
  swedish boolean; event_row core.events%rowtype; team_name text; kind text;
  title text; body text; callup_row core.callups%rowtype; raw_token text;
  response jsonb; thread_row core.message_threads%rowtype; reply jsonb;
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
    if outbox.payload_ref->>'thread_id' ~ '^[0-9a-fA-F-]{36}$' then
      select * into thread_row from core.message_threads where id = (outbox.payload_ref->>'thread_id')::uuid;
      -- Announcements are written by their creator only: no reply button.
      if thread_row.id is not null and thread_row.state = 'active' and thread_row.thread_type <> 'announcement' then
        delete from internal.push_reply_tokens
        where expires_at <= now() or consumed_at < now() - interval '1 day';
        raw_token := encode(extensions.gen_random_bytes(32), 'hex');
        insert into internal.push_reply_tokens(thread_id, recipient_profile_id, token_hash, expires_at)
        values (thread_row.id, outbox.recipient_profile_id, extensions.digest(raw_token, 'sha256'),
          now() + interval '7 days');
        reply := jsonb_build_object('thread_id', thread_row.id, 'token', raw_token);
      end if;
    end if;
  else
    return null;
  end if;
  return jsonb_build_object(
    'title', title,
    'body', body,
    'route', internal.notification_deep_link(outbox),
    'response', response,
    'reply', reply,
    'language', case when swedish then 'sv' else 'en' end,
    'targets', coalesce((
      select jsonb_agg(jsonb_build_object('endpoint_id', endpoint.id, 'platform', stored.platform,
        'token', extensions.pgp_sym_decrypt(stored.token_ciphertext, internal.push_token_key())))
      from core.notification_endpoints endpoint
      join internal.push_endpoint_tokens stored on stored.endpoint_id = endpoint.id
      where endpoint.profile_id = outbox.recipient_profile_id and endpoint.channel = 'push'
        and endpoint.state = 'active'), '[]'::jsonb));
end;$$;

-- One reply from a notification. A repeated send (a retry after a lost
-- reply) sends nothing new; an expired or unknown token, or a thread the
-- recipient can no longer write in, raises.
create or replace function internal.reply_from_push(raw_token text, reply_body text, idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare token_row internal.push_reply_tokens%rowtype;
  previous_sub text; previous_claims text; result jsonb;
begin
  if current_user not in ('postgres', 'service_role') then raise insufficient_privilege; end if;
  if raw_token is null or raw_token !~ '^[0-9a-f]{64}$' or idempotency_key is null
    or reply_body is null or length(btrim(reply_body)) not between 1 and 4000 then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  select * into token_row from internal.push_reply_tokens
  where token_hash = extensions.digest(raw_token, 'sha256') for update;
  if token_row.id is null or token_row.expires_at <= now() then
    raise insufficient_privilege using message = 'invalid_or_expired_token';
  end if;
  if token_row.consumed_at is not null then
    return jsonb_build_object('sent', true, 'repeated', true);
  end if;
  -- Send as the recipient, with the app's own rules; the claims are
  -- transaction-local and restored afterwards.
  previous_sub := current_setting('request.jwt.claim.sub', true);
  previous_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claim.sub', token_row.recipient_profile_id::text, true);
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', token_row.recipient_profile_id, 'role', 'authenticated')::text, true);
  result := internal.send_message_for_actor(token_row.thread_id, btrim(reply_body), idempotency_key);
  perform set_config('request.jwt.claim.sub', coalesce(previous_sub, ''), true);
  perform set_config('request.jwt.claims', coalesce(previous_claims, ''), true);
  update internal.push_reply_tokens set consumed_at = now() where id = token_row.id;
  return jsonb_build_object('sent', true, 'message_id', result->>'message_id');
end;$$;

create or replace function api.reply_from_push(raw_token text, reply_body text, idempotency_key uuid)
returns jsonb language sql security invoker set search_path = '' as
$$select internal.reply_from_push(raw_token, reply_body, idempotency_key)$$;

revoke all on function internal.reply_from_push(text, text, uuid),
  api.reply_from_push(text, text, uuid) from public, anon, authenticated;
grant execute on function internal.reply_from_push(text, text, uuid),
  api.reply_from_push(text, text, uuid) to service_role;

insert into internal.migration_provenance (migration_name, source_kind, source_reference)
select '20261025090000_push_message_reply', 'greenfield',
  'Reply to a message from its notification: single-use reply token, service-role send'
where not exists (select 1 from internal.migration_provenance where migration_name = '20261025090000_push_message_reply');
notify pgrst, 'reload schema';
