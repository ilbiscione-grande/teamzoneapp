-- Webtools Tacticsboard, live lessons, step 1: the one who presents a
-- project starts a live session with a short code; participants join with
-- it and follow the board as it is shown. The board's moves go over a
-- private Realtime channel "tactics-live:<session>": only the host
-- broadcasts on it, participants only listen and say they are there
-- (presence). The host chooses whether guests (Supabase anonymous
-- sign-ins) may join or a login is required; turning guests off removes
-- those already in. A session not ended by hand counts as over after 12
-- hours.

create table core.tactics_live_sessions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references core.tactics_projects(id) on delete cascade,
  host_id uuid not null references core.profiles(id),
  code text not null check (code ~ '^[A-Z2-9]{6}$'),
  allow_guests boolean not null default true,
  status text not null default 'live' check (status in ('live', 'ended')),
  created_at timestamptz not null default now(),
  ended_at timestamptz
);
create unique index tactics_live_sessions_code on core.tactics_live_sessions (code) where status = 'live';
create index tactics_live_sessions_project on core.tactics_live_sessions (project_id, created_at desc);

create table core.tactics_live_participants (
  session_id uuid not null references core.tactics_live_sessions(id) on delete cascade,
  profile_id uuid not null,
  display_name text not null check (length(display_name) between 1 and 40),
  is_guest boolean not null,
  joined_at timestamptz not null default now(),
  primary key (session_id, profile_id)
);

alter table core.tactics_live_sessions enable row level security;
alter table core.tactics_live_participants enable row level security;
revoke all on core.tactics_live_sessions, core.tactics_live_participants from public, anon, authenticated;

-- An anonymous sign-in is a guest.
create or replace function internal.tactics_live_actor_is_guest()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false)
$$;

create or replace function internal.tactics_live_is_open(session core.tactics_live_sessions)
returns boolean language sql stable security definer set search_path = '' as $$
  select session.status = 'live' and session.created_at > now() - interval '12 hours'
$$;

create or replace function internal.tactics_live_summary(session core.tactics_live_sessions)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', session.id, 'code', session.code, 'project_id', session.project_id,
    'allow_guests', session.allow_guests, 'live', internal.tactics_live_is_open(session),
    'created_at', session.created_at
  )
$$;

-- Six letters and digits that cannot be mistaken for one another.
create or replace function internal.tactics_live_new_code()
returns text language plpgsql volatile security definer set search_path = '' as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  bytes bytea;
  candidate text;
begin
  loop
    bytes := uuid_send(gen_random_uuid());
    candidate := '';
    for i in 0..5 loop candidate := candidate || substr(alphabet, get_byte(bytes, i) % 32 + 1, 1); end loop;
    exit when not exists (select 1 from core.tactics_live_sessions session where session.code = candidate and session.status = 'live');
  end loop;
  return candidate;
end;
$$;

create or replace function internal.tactics_live_require_host(target_session_id uuid)
returns core.tactics_live_sessions language plpgsql stable security definer set search_path = '' as $$
declare session core.tactics_live_sessions;
begin
  select * into session from core.tactics_live_sessions where id = target_session_id;
  if session.id is null or session.host_id is distinct from auth.uid() then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return session;
end;
$$;

-- Starts a live session for one of your projects, or hands back the one running.
create or replace function internal.start_tactics_live_for_actor(target_project_id uuid, guests_allowed boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare session core.tactics_live_sessions;
begin
  if auth.uid() is null or internal.tactics_live_actor_is_guest() then raise insufficient_privilege using message = 'not_signed_in'; end if;
  if not exists (select 1 from core.tactics_projects where id = target_project_id and owner_id = auth.uid()) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  update core.tactics_live_sessions set status = 'ended', ended_at = now()
  where project_id = target_project_id and status = 'live' and created_at <= now() - interval '12 hours';
  select * into session from core.tactics_live_sessions
  where project_id = target_project_id and host_id = auth.uid() and status = 'live'
  order by created_at desc limit 1;
  if session.id is null then
    insert into core.tactics_live_sessions (project_id, host_id, code, allow_guests)
    values (target_project_id, auth.uid(), internal.tactics_live_new_code(), coalesce(guests_allowed, true))
    returning * into session;
  end if;
  return internal.tactics_live_summary(session);
end;
$$;

-- Your running session for a project, if any (after a reload).
create or replace function internal.get_tactics_live_for_actor(target_project_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select internal.tactics_live_summary(session)
  from core.tactics_live_sessions session
  where session.project_id = target_project_id and session.host_id = auth.uid() and internal.tactics_live_is_open(session)
  order by session.created_at desc limit 1
$$;

-- Guests allowed or not; turned off, the guests already in are removed.
create or replace function internal.set_tactics_live_guests_for_actor(target_session_id uuid, guests_allowed boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare session core.tactics_live_sessions;
begin
  session := internal.tactics_live_require_host(target_session_id);
  update core.tactics_live_sessions set allow_guests = guests_allowed where id = session.id returning * into session;
  if not guests_allowed then delete from core.tactics_live_participants where session_id = session.id and is_guest; end if;
  return internal.tactics_live_summary(session);
end;
$$;

create or replace function internal.end_tactics_live_for_actor(target_session_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare session core.tactics_live_sessions;
begin
  session := internal.tactics_live_require_host(target_session_id);
  update core.tactics_live_sessions set status = 'ended', ended_at = coalesce(ended_at, now()) where id = session.id;
end;
$$;

-- Joining with the code: the board as last saved, the session and the name shown.
create or replace function internal.join_tactics_live_for_actor(target_code text, participant_name text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  session core.tactics_live_sessions;
  project core.tactics_projects;
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
  on conflict (session_id, profile_id) do update set display_name = excluded.display_name, is_guest = excluded.is_guest;
  select * into project from core.tactics_projects where id = session.project_id;
  return internal.tactics_live_summary(session) || jsonb_build_object(
    'name', project.name, 'kind', project.kind, 'document', project.document, 'participant_name', name,
    'host_name', coalesce(nullif(btrim((select display_name from core.profiles where id = session.host_id)), ''), 'Läraren')
  );
end;
$$;

-- Who may listen to a session's channel and who may send on it.
create or replace function internal.tactics_live_topic_session(topic text)
returns core.tactics_live_sessions language sql stable security definer set search_path = '' as $$
  select session.* from core.tactics_live_sessions session
  where topic ~ '^tactics-live:[0-9a-fA-F-]{36}$'
    and session.id = substring(topic from '^tactics-live:([0-9a-fA-F-]{36})$')::uuid
$$;

create or replace function internal.tactics_live_can_listen(topic text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((
    select internal.tactics_live_is_open(session) and (
      session.host_id = auth.uid()
      or exists (select 1 from core.tactics_live_participants participant where participant.session_id = session.id and participant.profile_id = auth.uid())
    )
    from internal.tactics_live_topic_session(topic) session where session.id is not null
  ), false)
$$;

create or replace function internal.tactics_live_can_broadcast(topic text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((
    select internal.tactics_live_is_open(session) and session.host_id = auth.uid()
    from internal.tactics_live_topic_session(topic) session where session.id is not null
  ), false)
$$;

create policy teamzone_tactics_live_select on realtime.messages for select to authenticated using (
  realtime.messages.extension in ('broadcast', 'presence')
  and (select realtime.topic()) like 'tactics-live:%'
  and internal.tactics_live_can_listen((select realtime.topic()))
);

create policy teamzone_tactics_live_insert on realtime.messages for insert to authenticated with check (
  (select realtime.topic()) like 'tactics-live:%'
  and (
    (realtime.messages.extension = 'broadcast' and internal.tactics_live_can_broadcast((select realtime.topic())))
    or (realtime.messages.extension = 'presence' and internal.tactics_live_can_listen((select realtime.topic())))
  )
);

create or replace function api.start_tactics_live(target_project_id uuid, guests_allowed boolean) returns jsonb
language sql security invoker set search_path = '' as $$ select internal.start_tactics_live_for_actor(target_project_id, guests_allowed) $$;
create or replace function api.get_tactics_live(target_project_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.get_tactics_live_for_actor(target_project_id) $$;
create or replace function api.set_tactics_live_guests(target_session_id uuid, guests_allowed boolean) returns jsonb
language sql security invoker set search_path = '' as $$ select internal.set_tactics_live_guests_for_actor(target_session_id, guests_allowed) $$;
create or replace function api.end_tactics_live(target_session_id uuid) returns void
language sql security invoker set search_path = '' as $$ select internal.end_tactics_live_for_actor(target_session_id) $$;
create or replace function api.join_tactics_live(target_code text, participant_name text) returns jsonb
language sql security invoker set search_path = '' as $$ select internal.join_tactics_live_for_actor(target_code, participant_name) $$;

revoke all on function
  internal.tactics_live_actor_is_guest(), internal.tactics_live_is_open(core.tactics_live_sessions),
  internal.tactics_live_summary(core.tactics_live_sessions), internal.tactics_live_new_code(),
  internal.tactics_live_require_host(uuid), internal.start_tactics_live_for_actor(uuid, boolean),
  internal.get_tactics_live_for_actor(uuid), internal.set_tactics_live_guests_for_actor(uuid, boolean),
  internal.end_tactics_live_for_actor(uuid), internal.join_tactics_live_for_actor(text, text),
  internal.tactics_live_topic_session(text), internal.tactics_live_can_listen(text), internal.tactics_live_can_broadcast(text),
  api.start_tactics_live(uuid, boolean), api.get_tactics_live(uuid), api.set_tactics_live_guests(uuid, boolean),
  api.end_tactics_live(uuid), api.join_tactics_live(text, text)
from public, anon, authenticated;
grant execute on function
  internal.tactics_live_actor_is_guest(), internal.tactics_live_is_open(core.tactics_live_sessions),
  internal.tactics_live_summary(core.tactics_live_sessions), internal.tactics_live_new_code(),
  internal.tactics_live_require_host(uuid), internal.start_tactics_live_for_actor(uuid, boolean),
  internal.get_tactics_live_for_actor(uuid), internal.set_tactics_live_guests_for_actor(uuid, boolean),
  internal.end_tactics_live_for_actor(uuid), internal.join_tactics_live_for_actor(text, text),
  internal.tactics_live_topic_session(text), internal.tactics_live_can_listen(text), internal.tactics_live_can_broadcast(text),
  api.start_tactics_live(uuid, boolean), api.get_tactics_live(uuid), api.set_tactics_live_guests(uuid, boolean),
  api.end_tactics_live(uuid), api.join_tactics_live(text, text)
to authenticated;
