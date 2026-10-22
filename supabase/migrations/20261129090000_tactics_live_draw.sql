-- Webtools Tacticsboard, live lessons, step 3: participants draw, and one
-- of them may be given the floor. The host chooses the drawing: off, own
-- notes (kept in the participant's browser, nothing here) or a shared
-- layer everyone sees, which the host clears. A stroke on the shared layer
-- is stored, so someone joining late sees it, and sent on by the database.
-- The participant given the floor moves objects on the host's board: the
-- moves go through here to everyone, and the host's board takes them in
-- when they are dropped. Nothing a participant sends goes on the channel
-- unchecked.

alter table core.tactics_live_sessions
  add column draw_mode text not null default 'off' check (draw_mode in ('off', 'own', 'shared')),
  add column floor_holder uuid;

create table core.tactics_live_strokes (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references core.tactics_live_sessions(id) on delete cascade,
  board_id text not null check (length(board_id) between 1 and 80),
  profile_id uuid not null,
  display_name text not null,
  color text not null check (color ~ '^#[0-9a-f]{6}$'),
  points jsonb not null,
  created_at timestamptz not null default now()
);
create index tactics_live_strokes_session on core.tactics_live_strokes (session_id, created_at);
alter table core.tactics_live_strokes enable row level security;
-- A stroke is activity, as a message is (20261128090000).
create trigger tactics_live_strokes_touch after insert on core.tactics_live_strokes
  for each row execute function internal.tactics_live_touch_from_row();
revoke all on core.tactics_live_strokes from public, anon, authenticated;

create or replace function internal.tactics_live_summary(session core.tactics_live_sessions)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', session.id, 'code', session.code, 'project_id', session.project_id,
    'allow_guests', session.allow_guests, 'live', internal.tactics_live_is_open(session),
    'chat_mode', session.chat_mode, 'hands', session.hands, 'draw_mode', session.draw_mode,
    'floor_holder', session.floor_holder,
    'floor_name', (select participant.display_name from core.tactics_live_participants participant
                   where participant.session_id = session.id and participant.profile_id = session.floor_holder),
    'created_at', session.created_at
  )
$$;

create or replace function internal.tactics_live_stroke_json(stroke core.tactics_live_strokes)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', stroke.id, 'board_id', stroke.board_id, 'profile_id', stroke.profile_id,
    'name', stroke.display_name, 'color', stroke.color, 'points', stroke.points, 'created_at', stroke.created_at)
$$;

-- The session, when the one asking is in it (host or participant).
create or replace function internal.tactics_live_member_session(target_session_id uuid)
returns core.tactics_live_sessions language plpgsql stable security definer set search_path = '' as $$
declare session core.tactics_live_sessions;
begin
  select * into session from core.tactics_live_sessions where id = target_session_id;
  if session.id is null or not internal.tactics_live_is_open(session) or (
    session.host_id is distinct from auth.uid()
    and not exists (select 1 from core.tactics_live_participants where session_id = session.id and profile_id = auth.uid())
  ) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return session;
end;
$$;

create or replace function internal.set_tactics_live_drawing_for_actor(target_session_id uuid, new_draw_mode text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare session core.tactics_live_sessions;
begin
  session := internal.tactics_live_require_host(target_session_id);
  if new_draw_mode not in ('off', 'own', 'shared') then raise invalid_parameter_value using message = 'invalid_draw_mode'; end if;
  update core.tactics_live_sessions set draw_mode = new_draw_mode where id = session.id returning * into session;
  return internal.tactics_live_summary(session);
end;
$$;

-- A stroke on the shared layer: pitch metres as x, y pairs, at most 300 points, 30 strokes a minute each.
create or replace function internal.add_tactics_live_stroke_for_actor(target_session_id uuid, target_board_id text, stroke_color text, stroke_points jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  session core.tactics_live_sessions;
  host boolean;
  saved core.tactics_live_strokes;
  payload jsonb;
begin
  session := internal.tactics_live_member_session(target_session_id);
  host := session.host_id = auth.uid();
  if not host and session.draw_mode <> 'shared' then raise insufficient_privilege using message = 'drawing_off'; end if;
  if jsonb_typeof(stroke_points) is distinct from 'array' or jsonb_array_length(stroke_points) not between 4 and 600
    or jsonb_array_length(stroke_points) % 2 <> 0
    or exists (select 1 from jsonb_array_elements(stroke_points) point
               where jsonb_typeof(point) <> 'number' or (point #>> '{}')::numeric not between -60 and 170) then
    raise invalid_parameter_value using message = 'invalid_stroke';
  end if;
  if coalesce(stroke_color, '') !~ '^#[0-9a-f]{6}$' or length(coalesce(target_board_id, '')) not between 1 and 80 then
    raise invalid_parameter_value using message = 'invalid_stroke';
  end if;
  if (select count(*) from core.tactics_live_strokes
      where session_id = session.id and profile_id = auth.uid() and created_at > now() - interval '1 minute') >= 30 then
    raise check_violation using message = 'too_fast';
  end if;
  insert into core.tactics_live_strokes (session_id, board_id, profile_id, display_name, color, points)
  values (session.id, target_board_id, auth.uid(),
    case when host then 'Läraren' else (select display_name from core.tactics_live_participants where session_id = session.id and profile_id = auth.uid()) end,
    stroke_color, stroke_points)
  returning * into saved;
  payload := internal.tactics_live_stroke_json(saved);
  perform realtime.send(payload, 'stroke', 'tactics-live:' || session.id::text, true);
  return payload;
end;
$$;

create or replace function internal.list_tactics_live_strokes_for_actor(target_session_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare session core.tactics_live_sessions;
begin
  session := internal.tactics_live_member_session(target_session_id);
  return coalesce((select jsonb_agg(internal.tactics_live_stroke_json(stroke) order by stroke.created_at)
    from core.tactics_live_strokes stroke where stroke.session_id = session.id), '[]'::jsonb);
end;
$$;

-- The host clears the shared layer on one board, or on all of them.
create or replace function internal.clear_tactics_live_strokes_for_actor(target_session_id uuid, target_board_id text)
returns void language plpgsql security definer set search_path = '' as $$
declare session core.tactics_live_sessions;
begin
  session := internal.tactics_live_require_host(target_session_id);
  delete from core.tactics_live_strokes where session_id = session.id and (target_board_id is null or board_id = target_board_id);
  perform realtime.send(jsonb_build_object('boardId', target_board_id), 'strokes-cleared', 'tactics-live:' || session.id::text, true);
end;
$$;

-- The floor to one participant, or back to the host (null).
create or replace function internal.give_tactics_live_floor_for_actor(target_session_id uuid, target_profile_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare session core.tactics_live_sessions;
begin
  session := internal.tactics_live_require_host(target_session_id);
  if target_profile_id is not null and not exists (
    select 1 from core.tactics_live_participants where session_id = session.id and profile_id = target_profile_id
  ) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  update core.tactics_live_sessions set floor_holder = target_profile_id where id = session.id returning * into session;
  perform realtime.send(jsonb_build_object('profileId', session.floor_holder, 'name', internal.tactics_live_summary(session) ->> 'floor_name'),
    'floor', 'tactics-live:' || session.id::text, true);
  return internal.tactics_live_summary(session);
end;
$$;

-- The one with the floor moves objects: where each is now, and whether they were dropped there.
create or replace function internal.move_tactics_live_floor_for_actor(
  target_session_id uuid, target_board_id text, target_frame_index integer, object_moves jsonb, dropped boolean
) returns void language plpgsql security definer set search_path = '' as $$
declare
  session core.tactics_live_sessions;
  clean jsonb;
begin
  session := internal.tactics_live_member_session(target_session_id);
  if session.floor_holder is distinct from auth.uid() then raise insufficient_privilege using message = 'no_floor'; end if;
  if jsonb_typeof(object_moves) is distinct from 'object' or (select count(*) from jsonb_object_keys(object_moves)) not between 1 and 40
    or exists (select 1 from jsonb_each(object_moves) move
               where jsonb_typeof(move.value -> 'x') is distinct from 'number' or jsonb_typeof(move.value -> 'y') is distinct from 'number'
                  or (move.value ->> 'x')::numeric not between -60 and 170 or (move.value ->> 'y')::numeric not between -60 and 130
                  or length(move.key) > 80)
    or coalesce(target_frame_index, -1) not between 0 and 500 or length(coalesce(target_board_id, '')) not between 1 and 80 then
    raise invalid_parameter_value using message = 'invalid_move';
  end if;
  select jsonb_object_agg(move.key, jsonb_build_object('x', move.value -> 'x', 'y', move.value -> 'y')) into clean
  from jsonb_each(object_moves) move;
  perform realtime.send(jsonb_build_object('boardId', target_board_id, 'frameIndex', target_frame_index, 'moves', clean,
    'dropped', coalesce(dropped, false), 'by', auth.uid()), 'floor-move', 'tactics-live:' || session.id::text, true);
end;
$$;

create or replace function api.set_tactics_live_drawing(target_session_id uuid, new_draw_mode text) returns jsonb
language sql security invoker set search_path = '' as $$ select internal.set_tactics_live_drawing_for_actor(target_session_id, new_draw_mode) $$;
create or replace function api.add_tactics_live_stroke(target_session_id uuid, target_board_id text, stroke_color text, stroke_points jsonb) returns jsonb
language sql security invoker set search_path = '' as $$ select internal.add_tactics_live_stroke_for_actor(target_session_id, target_board_id, stroke_color, stroke_points) $$;
create or replace function api.list_tactics_live_strokes(target_session_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.list_tactics_live_strokes_for_actor(target_session_id) $$;
create or replace function api.clear_tactics_live_strokes(target_session_id uuid, target_board_id text) returns void
language sql security invoker set search_path = '' as $$ select internal.clear_tactics_live_strokes_for_actor(target_session_id, target_board_id) $$;
create or replace function api.give_tactics_live_floor(target_session_id uuid, target_profile_id uuid) returns jsonb
language sql security invoker set search_path = '' as $$ select internal.give_tactics_live_floor_for_actor(target_session_id, target_profile_id) $$;
create or replace function api.move_tactics_live_floor(target_session_id uuid, target_board_id text, target_frame_index integer, object_moves jsonb, dropped boolean) returns void
language sql security invoker set search_path = '' as $$ select internal.move_tactics_live_floor_for_actor(target_session_id, target_board_id, target_frame_index, object_moves, dropped) $$;

revoke all on function
  internal.tactics_live_stroke_json(core.tactics_live_strokes), internal.tactics_live_member_session(uuid),
  internal.set_tactics_live_drawing_for_actor(uuid, text), internal.add_tactics_live_stroke_for_actor(uuid, text, text, jsonb),
  internal.list_tactics_live_strokes_for_actor(uuid), internal.clear_tactics_live_strokes_for_actor(uuid, text),
  internal.give_tactics_live_floor_for_actor(uuid, uuid), internal.move_tactics_live_floor_for_actor(uuid, text, integer, jsonb, boolean),
  api.set_tactics_live_drawing(uuid, text), api.add_tactics_live_stroke(uuid, text, text, jsonb), api.list_tactics_live_strokes(uuid),
  api.clear_tactics_live_strokes(uuid, text), api.give_tactics_live_floor(uuid, uuid), api.move_tactics_live_floor(uuid, text, integer, jsonb, boolean)
from public, anon, authenticated;
grant execute on function
  internal.tactics_live_stroke_json(core.tactics_live_strokes), internal.tactics_live_member_session(uuid),
  internal.set_tactics_live_drawing_for_actor(uuid, text), internal.add_tactics_live_stroke_for_actor(uuid, text, text, jsonb),
  internal.list_tactics_live_strokes_for_actor(uuid), internal.clear_tactics_live_strokes_for_actor(uuid, text),
  internal.give_tactics_live_floor_for_actor(uuid, uuid), internal.move_tactics_live_floor_for_actor(uuid, text, integer, jsonb, boolean),
  api.set_tactics_live_drawing(uuid, text), api.add_tactics_live_stroke(uuid, text, text, jsonb), api.list_tactics_live_strokes(uuid),
  api.clear_tactics_live_strokes(uuid, text), api.give_tactics_live_floor(uuid, uuid), api.move_tactics_live_floor(uuid, text, integer, jsonb, boolean)
to authenticated;
