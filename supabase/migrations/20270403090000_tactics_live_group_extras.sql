-- Webtools Tacticsboard, live lessons: group work, step 3 of
-- docs/implementation/tacticsboard-live-groups.md. Inside a group:
-- - Drawing on the group's copy.
-- - A chat of the group's own.
-- - A countdown the host sets for all groups.
-- Saving a group's solution as a new board is done in the host's editor,
-- from the copy the host already has.
--
-- A group's strokes and messages belong to the group and go with it, like
-- the rest of the sandbox. They go out on the group's channel, which the
-- group's members and the host hear. A shown group's strokes also go out on
-- the lesson's channel. The class's own drawing and chat leave the groups'
-- rows alone.

alter table core.tactics_live_strokes add column group_id uuid references core.tactics_live_groups(id) on delete cascade;
alter table core.tactics_live_messages add column group_id uuid references core.tactics_live_groups(id) on delete cascade;
alter table core.tactics_live_sessions add column groups_ends_at timestamptz;

-- Seconds left of the group work's time, or null when there is none (time already out is 0).
create or replace function internal.tactics_live_groups_ends_in(target_session_id uuid)
returns numeric language sql stable security definer set search_path = '' as $$
  select case when session.groups_ends_at is null then null
    else greatest(0, round(extract(epoch from session.groups_ends_at - now()))) end
  from core.tactics_live_sessions session where session.id = target_session_id
$$;

-- A group with its board, moves, drawing, chat and time left.
create or replace function internal.tactics_live_group_full(target core.tactics_live_groups)
returns jsonb language sql stable security definer set search_path = '' as $$
  select internal.tactics_live_group_summary(target) || jsonb_build_object(
    'board', target.board, 'moves', target.moves,
    'strokes', coalesce((select jsonb_agg(internal.tactics_live_stroke_json(stroke) order by stroke.created_at)
      from core.tactics_live_strokes stroke where stroke.group_id = target.id), '[]'::jsonb),
    'messages', coalesce((select jsonb_agg(internal.tactics_live_message_json(m) order by m.created_at) from (
      select * from core.tactics_live_messages message where message.group_id = target.id and message.deleted_at is null
      order by message.created_at desc limit 200) m), '[]'::jsonb),
    'ends_in', internal.tactics_live_groups_ends_in(target.session_id))
$$;

-- The participant's own group, for drawing and chatting in it.
create or replace function internal.tactics_live_own_group(session core.tactics_live_sessions)
returns core.tactics_live_groups language plpgsql stable security definer set search_path = '' as $$
declare mine core.tactics_live_groups;
begin
  select item.* into mine from core.tactics_live_groups item
  join core.tactics_live_participants participant on participant.group_id = item.id
  where participant.session_id = session.id and participant.profile_id = auth.uid();
  if mine.id is null then raise insufficient_privilege using message = 'no_group'; end if;
  return mine;
end;
$$;

-- A stroke on the group's copy: as on the shared layer (20261129090000), whatever the class's drawing mode.
create or replace function internal.add_tactics_live_group_stroke_for_actor(target_session_id uuid, stroke_color text, stroke_points jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  session core.tactics_live_sessions;
  mine core.tactics_live_groups;
  saved core.tactics_live_strokes;
  payload jsonb;
begin
  session := internal.tactics_live_member_session(target_session_id);
  mine := internal.tactics_live_own_group(session);
  if jsonb_typeof(stroke_points) is distinct from 'array' or jsonb_array_length(stroke_points) not between 4 and 600
    or jsonb_array_length(stroke_points) % 2 <> 0
    or exists (select 1 from jsonb_array_elements(stroke_points) point
               where jsonb_typeof(point) <> 'number' or (point #>> '{}')::numeric not between -60 and 170)
    or coalesce(stroke_color, '') !~ '^#[0-9a-f]{6}$' then
    raise invalid_parameter_value using message = 'invalid_stroke';
  end if;
  if (select count(*) from core.tactics_live_strokes
      where session_id = session.id and profile_id = auth.uid() and created_at > now() - interval '1 minute') >= 30 then
    raise check_violation using message = 'too_fast';
  end if;
  insert into core.tactics_live_strokes (session_id, board_id, profile_id, display_name, color, points, group_id)
  values (session.id, mine.board_id, auth.uid(),
    (select display_name from core.tactics_live_participants where session_id = session.id and profile_id = auth.uid()),
    stroke_color, stroke_points, mine.id)
  returning * into saved;
  payload := internal.tactics_live_stroke_json(saved) || jsonb_build_object('group_id', mine.id);
  perform realtime.send(payload, 'group-stroke', 'tactics-live-group:' || mine.id::text, true);
  if session.shown_group is not distinct from mine.id then
    perform realtime.send(payload, 'shown-stroke', 'tactics-live:' || session.id::text, true);
  end if;
  return payload;
end;
$$;

-- A message in the group's own chat: not when the host turned the participant's chat off; at most five in ten seconds.
create or replace function internal.send_tactics_live_group_message_for_actor(target_session_id uuid, message_body text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  session core.tactics_live_sessions;
  mine core.tactics_live_groups;
  participant core.tactics_live_participants;
  body text := btrim(coalesce(message_body, ''));
  saved core.tactics_live_messages;
  payload jsonb;
begin
  session := internal.tactics_live_member_session(target_session_id);
  mine := internal.tactics_live_own_group(session);
  select * into participant from core.tactics_live_participants where session_id = session.id and profile_id = auth.uid();
  if participant.muted then raise insufficient_privilege using message = 'muted'; end if;
  if length(body) not between 1 and 500 then raise invalid_parameter_value using message = 'invalid_message'; end if;
  if (select count(*) from core.tactics_live_messages
      where session_id = session.id and profile_id = auth.uid() and created_at > now() - interval '10 seconds') >= 5 then
    raise check_violation using message = 'too_fast';
  end if;
  insert into core.tactics_live_messages (session_id, profile_id, display_name, from_host, body, group_id)
  values (session.id, auth.uid(), participant.display_name, false, body, mine.id)
  returning * into saved;
  payload := internal.tactics_live_message_json(saved) || jsonb_build_object('group_id', mine.id);
  perform realtime.send(payload, 'group-chat', 'tactics-live-group:' || mine.id::text, true);
  return payload;
end;
$$;

-- The host sets the time for the group work, in minutes from now, or none (null).
create or replace function internal.set_tactics_live_groups_timer_for_actor(target_session_id uuid, minutes integer)
returns void language plpgsql security definer set search_path = '' as $$
declare session core.tactics_live_sessions;
begin
  session := internal.tactics_live_require_host(target_session_id);
  if not internal.tactics_live_is_open(session) then raise insufficient_privilege using message = 'not_found'; end if;
  if not exists (select 1 from core.tactics_live_groups where session_id = session.id) then
    raise insufficient_privilege using message = 'no_groups';
  end if;
  if minutes is not null and minutes not between 1 and 60 then raise invalid_parameter_value using message = 'invalid_minutes'; end if;
  update core.tactics_live_sessions
  set groups_ends_at = case when minutes is null then null else now() + make_interval(mins => minutes) end, last_activity_at = now()
  where id = session.id;
  perform realtime.send(jsonb_build_object('seconds', minutes * 60), 'groups-timer', 'tactics-live:' || session.id::text, true);
end;
$$;

-- No time left over from earlier group work. With no groups left nothing is
-- shown either; cleared here as well, since this update can run before the
-- foreign key's own "set null" and would otherwise point at a group that is gone.
create or replace function internal.tactics_live_groups_clear_timer()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update core.tactics_live_sessions set groups_ends_at = null, shown_group = null
  where id = old.session_id and groups_ends_at is not null
    and not exists (select 1 from core.tactics_live_groups where session_id = old.session_id);
  return null;
end;
$$;
create trigger tactics_live_groups_clear_timer after delete on core.tactics_live_groups
  for each row execute function internal.tactics_live_groups_clear_timer();

-- The class's shared layer and chat, as before, without the groups' rows.
create or replace function internal.list_tactics_live_strokes_for_actor(target_session_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare session core.tactics_live_sessions;
begin
  session := internal.tactics_live_member_session(target_session_id);
  return coalesce((select jsonb_agg(internal.tactics_live_stroke_json(stroke) order by stroke.created_at)
    from core.tactics_live_strokes stroke where stroke.session_id = session.id and stroke.group_id is null), '[]'::jsonb);
end;
$$;

create or replace function internal.clear_tactics_live_strokes_for_actor(target_session_id uuid, target_board_id text)
returns void language plpgsql security definer set search_path = '' as $$
declare session core.tactics_live_sessions;
begin
  session := internal.tactics_live_require_host(target_session_id);
  delete from core.tactics_live_strokes
  where session_id = session.id and group_id is null and (target_board_id is null or board_id = target_board_id);
  perform realtime.send(jsonb_build_object('boardId', target_board_id), 'strokes-cleared', 'tactics-live:' || session.id::text, true);
end;
$$;

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
    where message.session_id = session.id and message.deleted_at is null and message.group_id is null
      and (host or not message.to_host or message.profile_id = auth.uid())
    order by message.created_at desc limit 200
  ) m), '[]'::jsonb);
end;
$$;

create or replace function api.add_tactics_live_group_stroke(target_session_id uuid, stroke_color text, stroke_points jsonb) returns jsonb
language sql security invoker set search_path = '' as $$ select internal.add_tactics_live_group_stroke_for_actor(target_session_id, stroke_color, stroke_points) $$;
create or replace function api.send_tactics_live_group_message(target_session_id uuid, message_body text) returns jsonb
language sql security invoker set search_path = '' as $$ select internal.send_tactics_live_group_message_for_actor(target_session_id, message_body) $$;
create or replace function api.set_tactics_live_groups_timer(target_session_id uuid, minutes integer) returns void
language sql security invoker set search_path = '' as $$ select internal.set_tactics_live_groups_timer_for_actor(target_session_id, minutes) $$;

revoke all on function
  internal.tactics_live_groups_ends_in(uuid), internal.tactics_live_own_group(core.tactics_live_sessions),
  internal.add_tactics_live_group_stroke_for_actor(uuid, text, jsonb), internal.send_tactics_live_group_message_for_actor(uuid, text),
  internal.set_tactics_live_groups_timer_for_actor(uuid, integer),
  api.add_tactics_live_group_stroke(uuid, text, jsonb), api.send_tactics_live_group_message(uuid, text), api.set_tactics_live_groups_timer(uuid, integer)
from public, anon, authenticated;
revoke all on function internal.tactics_live_groups_clear_timer() from public, anon, authenticated;
grant execute on function
  internal.tactics_live_groups_ends_in(uuid), internal.tactics_live_own_group(core.tactics_live_sessions),
  internal.add_tactics_live_group_stroke_for_actor(uuid, text, jsonb), internal.send_tactics_live_group_message_for_actor(uuid, text),
  internal.set_tactics_live_groups_timer_for_actor(uuid, integer),
  api.add_tactics_live_group_stroke(uuid, text, jsonb), api.send_tactics_live_group_message(uuid, text), api.set_tactics_live_groups_timer(uuid, integer)
to authenticated;
