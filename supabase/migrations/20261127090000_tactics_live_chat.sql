-- Webtools Tacticsboard, live lessons, step 2: a chat and raised hands.
-- The host chooses the chat: off, on, or questions only (a participant's
-- message then reaches the host alone), and whether hands may be raised
-- (hands go over the channel's presence, nothing is stored). Messages are
-- kept, so someone joining late reads the chat so far; the host removes a
-- message or turns one participant's chat off. Participants never send on
-- the channel themselves: a message is stored here and sent on by the
-- database, to everyone or, for a question, on the host's own topic
-- "tactics-live-host:<session>".

alter table core.tactics_live_sessions
  add column chat_mode text not null default 'on' check (chat_mode in ('off', 'on', 'questions')),
  add column hands boolean not null default true;
alter table core.tactics_live_participants add column muted boolean not null default false;

create table core.tactics_live_messages (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references core.tactics_live_sessions(id) on delete cascade,
  profile_id uuid not null,
  display_name text not null,
  from_host boolean not null,
  to_host boolean not null default false,
  body text not null check (length(body) between 1 and 500),
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index tactics_live_messages_session on core.tactics_live_messages (session_id, created_at);
alter table core.tactics_live_messages enable row level security;
revoke all on core.tactics_live_messages from public, anon, authenticated;

create or replace function internal.tactics_live_summary(session core.tactics_live_sessions)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', session.id, 'code', session.code, 'project_id', session.project_id,
    'allow_guests', session.allow_guests, 'live', internal.tactics_live_is_open(session),
    'chat_mode', session.chat_mode, 'hands', session.hands, 'created_at', session.created_at
  )
$$;

create or replace function internal.tactics_live_message_json(message core.tactics_live_messages)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', message.id, 'profile_id', message.profile_id, 'name', message.display_name,
    'from_host', message.from_host, 'to_host', message.to_host, 'body', message.body, 'created_at', message.created_at
  )
$$;

-- Joining hands back whether the participant's chat is off as well.
create or replace function internal.join_tactics_live_for_actor(target_code text, participant_name text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  session core.tactics_live_sessions;
  project core.tactics_projects;
  joined core.tactics_live_participants;
  guest boolean := internal.tactics_live_actor_is_guest();
  name text := btrim(coalesce(participant_name, ''));
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  select * into session from core.tactics_live_sessions
  where code = upper(btrim(coalesce(target_code, ''))) and status = 'live' order by created_at desc limit 1;
  if session.id is null or not internal.tactics_live_is_open(session) then raise invalid_parameter_value using message = 'not_found'; end if;
  if guest and not session.allow_guests then raise insufficient_privilege using message = 'login_required'; end if;
  if name = '' and not guest then
    name := coalesce(nullif(btrim((select display_name from core.profiles where id = auth.uid())), ''), 'Deltagare');
  end if;
  if length(name) not between 1 and 40 then raise invalid_parameter_value using message = 'invalid_name'; end if;
  insert into core.tactics_live_participants (session_id, profile_id, display_name, is_guest)
  values (session.id, auth.uid(), name, guest)
  on conflict (session_id, profile_id) do update set display_name = excluded.display_name, is_guest = excluded.is_guest
  returning * into joined;
  select * into project from core.tactics_projects where id = session.project_id;
  return internal.tactics_live_summary(session) || jsonb_build_object(
    'name', project.name, 'kind', project.kind, 'document', project.document, 'participant_name', name, 'muted', joined.muted,
    'host_name', coalesce(nullif(btrim((select display_name from core.profiles where id = session.host_id)), ''), 'Läraren')
  );
end;
$$;

-- The host's own topic: questions and other things for the host alone.
create or replace function internal.tactics_live_host_topic_open(topic text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((
    select internal.tactics_live_is_open(session) and session.host_id = auth.uid()
    from core.tactics_live_sessions session
    where topic ~ '^tactics-live-host:[0-9a-fA-F-]{36}$'
      and session.id = substring(topic from '^tactics-live-host:([0-9a-fA-F-]{36})$')::uuid
  ), false)
$$;

create policy teamzone_tactics_live_host_select on realtime.messages for select to authenticated using (
  realtime.messages.extension = 'broadcast'
  and (select realtime.topic()) like 'tactics-live-host:%'
  and internal.tactics_live_host_topic_open((select realtime.topic()))
);

-- Sends a message: the host always; a participant when the chat is on and
-- theirs is not turned off, at most five in ten seconds.
create or replace function internal.send_tactics_live_message_for_actor(target_session_id uuid, message_body text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  session core.tactics_live_sessions;
  participant core.tactics_live_participants;
  host boolean;
  body text := btrim(coalesce(message_body, ''));
  saved core.tactics_live_messages;
  payload jsonb;
begin
  select * into session from core.tactics_live_sessions where id = target_session_id;
  if session.id is null or not internal.tactics_live_is_open(session) then raise insufficient_privilege using message = 'not_found'; end if;
  host := session.host_id = auth.uid();
  if not host then
    select * into participant from core.tactics_live_participants where session_id = session.id and profile_id = auth.uid();
    if participant.profile_id is null then raise insufficient_privilege using message = 'not_found'; end if;
    if session.chat_mode = 'off' then raise insufficient_privilege using message = 'chat_off'; end if;
    if participant.muted then raise insufficient_privilege using message = 'muted'; end if;
  end if;
  if length(body) not between 1 and 500 then raise invalid_parameter_value using message = 'invalid_message'; end if;
  if (select count(*) from core.tactics_live_messages
      where session_id = session.id and profile_id = auth.uid() and created_at > now() - interval '10 seconds') >= 5 then
    raise check_violation using message = 'too_fast';
  end if;
  insert into core.tactics_live_messages (session_id, profile_id, display_name, from_host, to_host, body)
  values (session.id, auth.uid(),
    case when host then coalesce(nullif(btrim((select display_name from core.profiles where id = auth.uid())), ''), 'Läraren') else participant.display_name end,
    host, not host and session.chat_mode = 'questions', body)
  returning * into saved;
  payload := internal.tactics_live_message_json(saved);
  perform realtime.send(payload, 'chat', case when saved.to_host then 'tactics-live-host:' else 'tactics-live:' end || session.id::text, true);
  return payload;
end;
$$;

-- The chat so far: what everyone sees, the participant's own questions, and for the host all of it.
create or replace function internal.list_tactics_live_messages_for_actor(target_session_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  session core.tactics_live_sessions;
  host boolean;
begin
  select * into session from core.tactics_live_sessions where id = target_session_id;
  if session.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  host := session.host_id = auth.uid();
  if not host and not exists (select 1 from core.tactics_live_participants where session_id = session.id and profile_id = auth.uid()) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return coalesce((select jsonb_agg(internal.tactics_live_message_json(m) order by m.created_at) from (
    select * from core.tactics_live_messages message
    where message.session_id = session.id and message.deleted_at is null
      and (host or not message.to_host or message.profile_id = auth.uid())
    order by message.created_at desc limit 200
  ) m), '[]'::jsonb);
end;
$$;

create or replace function internal.delete_tactics_live_message_for_actor(target_message_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare message core.tactics_live_messages;
begin
  select * into message from core.tactics_live_messages where id = target_message_id;
  if message.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  perform internal.tactics_live_require_host(message.session_id);
  update core.tactics_live_messages set deleted_at = now() where id = message.id;
  perform realtime.send(jsonb_build_object('id', message.id), 'chat-deleted', 'tactics-live:' || message.session_id::text, true);
  perform realtime.send(jsonb_build_object('id', message.id), 'chat-deleted', 'tactics-live-host:' || message.session_id::text, true);
end;
$$;

create or replace function internal.set_tactics_live_chat_for_actor(target_session_id uuid, new_chat_mode text, hands_allowed boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare session core.tactics_live_sessions;
begin
  session := internal.tactics_live_require_host(target_session_id);
  if new_chat_mode not in ('off', 'on', 'questions') then raise invalid_parameter_value using message = 'invalid_chat_mode'; end if;
  update core.tactics_live_sessions set chat_mode = new_chat_mode, hands = coalesce(hands_allowed, hands)
  where id = session.id returning * into session;
  return internal.tactics_live_summary(session);
end;
$$;

-- One participant's chat off or on again.
create or replace function internal.mute_tactics_live_participant_for_actor(target_session_id uuid, target_profile_id uuid, is_muted boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform internal.tactics_live_require_host(target_session_id);
  update core.tactics_live_participants set muted = coalesce(is_muted, false)
  where session_id = target_session_id and profile_id = target_profile_id;
  if not found then raise insufficient_privilege using message = 'not_found'; end if;
end;
$$;

create or replace function api.send_tactics_live_message(target_session_id uuid, message_body text) returns jsonb
language sql security invoker set search_path = '' as $$ select internal.send_tactics_live_message_for_actor(target_session_id, message_body) $$;
create or replace function api.list_tactics_live_messages(target_session_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.list_tactics_live_messages_for_actor(target_session_id) $$;
create or replace function api.delete_tactics_live_message(target_message_id uuid) returns void
language sql security invoker set search_path = '' as $$ select internal.delete_tactics_live_message_for_actor(target_message_id) $$;
create or replace function api.set_tactics_live_chat(target_session_id uuid, new_chat_mode text, hands_allowed boolean) returns jsonb
language sql security invoker set search_path = '' as $$ select internal.set_tactics_live_chat_for_actor(target_session_id, new_chat_mode, hands_allowed) $$;
create or replace function api.mute_tactics_live_participant(target_session_id uuid, target_profile_id uuid, is_muted boolean) returns void
language sql security invoker set search_path = '' as $$ select internal.mute_tactics_live_participant_for_actor(target_session_id, target_profile_id, is_muted) $$;

revoke all on function
  internal.tactics_live_message_json(core.tactics_live_messages), internal.tactics_live_host_topic_open(text),
  internal.send_tactics_live_message_for_actor(uuid, text), internal.list_tactics_live_messages_for_actor(uuid),
  internal.delete_tactics_live_message_for_actor(uuid), internal.set_tactics_live_chat_for_actor(uuid, text, boolean),
  internal.mute_tactics_live_participant_for_actor(uuid, uuid, boolean),
  api.send_tactics_live_message(uuid, text), api.list_tactics_live_messages(uuid), api.delete_tactics_live_message(uuid),
  api.set_tactics_live_chat(uuid, text, boolean), api.mute_tactics_live_participant(uuid, uuid, boolean)
from public, anon, authenticated;
grant execute on function
  internal.tactics_live_message_json(core.tactics_live_messages), internal.tactics_live_host_topic_open(text),
  internal.send_tactics_live_message_for_actor(uuid, text), internal.list_tactics_live_messages_for_actor(uuid),
  internal.delete_tactics_live_message_for_actor(uuid), internal.set_tactics_live_chat_for_actor(uuid, text, boolean),
  internal.mute_tactics_live_participant_for_actor(uuid, uuid, boolean),
  api.send_tactics_live_message(uuid, text), api.list_tactics_live_messages(uuid), api.delete_tactics_live_message(uuid),
  api.set_tactics_live_chat(uuid, text, boolean), api.mute_tactics_live_participant(uuid, uuid, boolean)
to authenticated;
