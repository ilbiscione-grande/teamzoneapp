-- Webtools Tacticsboard, live lessons: a session left running ends by
-- itself after 30 minutes without activity (and still after 12 hours at
-- most). Activity is what the host does on the board (the host's page
-- reports it), a chat message, or someone joining. Participants ask now
-- and then whether the lesson is still on.

alter table core.tactics_live_sessions add column last_activity_at timestamptz not null default now();

create or replace function internal.tactics_live_is_open(session core.tactics_live_sessions)
returns boolean language sql stable security definer set search_path = '' as $$
  select session.status = 'live'
    and session.created_at > now() - interval '12 hours'
    and session.last_activity_at > now() - interval '30 minutes'
$$;

-- A message or someone joining is activity.
create or replace function internal.tactics_live_touch_from_row()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update core.tactics_live_sessions set last_activity_at = now()
  where id = new.session_id and status = 'live' and last_activity_at < now() - interval '10 seconds';
  return new;
end;
$$;
create trigger tactics_live_messages_touch after insert on core.tactics_live_messages
  for each row execute function internal.tactics_live_touch_from_row();
create trigger tactics_live_participants_touch after insert or update on core.tactics_live_participants
  for each row execute function internal.tactics_live_touch_from_row();

-- The host's page says the host is doing something; false when the session is over.
create or replace function internal.touch_tactics_live_for_actor(target_session_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare session core.tactics_live_sessions;
begin
  session := internal.tactics_live_require_host(target_session_id);
  if not internal.tactics_live_is_open(session) then return false; end if;
  update core.tactics_live_sessions set last_activity_at = now() where id = session.id;
  return true;
end;
$$;

-- Whether the lesson is still on, for its host and participants.
create or replace function internal.tactics_live_open_for_actor(target_session_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((
    select internal.tactics_live_is_open(session)
    from core.tactics_live_sessions session
    where session.id = target_session_id and (
      session.host_id = auth.uid()
      or exists (select 1 from core.tactics_live_participants participant where participant.session_id = session.id and participant.profile_id = auth.uid())
    )
  ), false)
$$;

-- Starting again ends the project's sessions that are over in all but name.
create or replace function internal.start_tactics_live_for_actor(target_project_id uuid, guests_allowed boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare session core.tactics_live_sessions;
begin
  if auth.uid() is null or internal.tactics_live_actor_is_guest() then raise insufficient_privilege using message = 'not_signed_in'; end if;
  if not exists (select 1 from core.tactics_projects where id = target_project_id and owner_id = auth.uid()) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  update core.tactics_live_sessions running set status = 'ended', ended_at = now()
  where running.project_id = target_project_id and running.status = 'live' and not internal.tactics_live_is_open(running);
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

create or replace function api.touch_tactics_live(target_session_id uuid) returns boolean
language sql security invoker set search_path = '' as $$ select internal.touch_tactics_live_for_actor(target_session_id) $$;
create or replace function api.tactics_live_open(target_session_id uuid) returns boolean
language sql stable security invoker set search_path = '' as $$ select internal.tactics_live_open_for_actor(target_session_id) $$;

revoke all on function
  internal.tactics_live_touch_from_row(), internal.touch_tactics_live_for_actor(uuid), internal.tactics_live_open_for_actor(uuid),
  api.touch_tactics_live(uuid), api.tactics_live_open(uuid)
from public, anon, authenticated;
grant execute on function
  internal.touch_tactics_live_for_actor(uuid), internal.tactics_live_open_for_actor(uuid),
  api.touch_tactics_live(uuid), api.tactics_live_open(uuid)
to authenticated;
