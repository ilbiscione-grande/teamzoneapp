-- Webtools Tacticsboard, live lessons: group work, step 2 of
-- docs/implementation/tacticsboard-live-groups.md. The host's overview of
-- the groups. The host:
-- - sees every group's copy as it changes,
-- - moves a participant to another group,
-- - shows one group's copy to everyone, one group at a time.
--
-- The host listens on every group's channel (step 1 lets the host in).
-- While a group is shown, its moves also go out on the lesson's channel as
-- "shown-move", so the whole class sees them. The group itself still
-- works on its copy.

alter table core.tactics_live_sessions
  add column shown_group uuid references core.tactics_live_groups(id) on delete set null;

-- A group with its board and moves.
create or replace function internal.tactics_live_group_full(target core.tactics_live_groups)
returns jsonb language sql stable security definer set search_path = '' as $$
  select internal.tactics_live_group_summary(target) || jsonb_build_object('board', target.board, 'moves', target.moves)
$$;

-- The host's list: every group with its copy, and which one is shown to everyone.
create or replace function internal.tactics_live_groups_json(target_session_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(internal.tactics_live_group_full(item)
    || jsonb_build_object('shown', session.shown_group is not distinct from item.id) order by item.number), '[]'::jsonb)
  from core.tactics_live_groups item
  join core.tactics_live_sessions session on session.id = item.session_id
  where item.session_id = target_session_id
$$;

create or replace function internal.get_tactics_live_group_for_actor(target_session_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  session core.tactics_live_sessions;
  mine core.tactics_live_groups;
begin
  session := internal.tactics_live_member_session(target_session_id);
  if session.host_id = auth.uid() then return null; end if;
  select item.* into mine from core.tactics_live_groups item
  join core.tactics_live_participants participant on participant.group_id = item.id
  where participant.session_id = session.id and participant.profile_id = auth.uid();
  if mine.id is null then
    select item.* into mine from core.tactics_live_groups item
    where item.session_id = session.id
    order by (select count(*) from core.tactics_live_participants participant where participant.group_id = item.id), item.number
    limit 1;
    if mine.id is null then return null; end if;
    update core.tactics_live_participants set group_id = mine.id where session_id = session.id and profile_id = auth.uid();
  end if;
  return internal.tactics_live_group_full(mine);
end;
$$;

-- The host moves a participant to another group of the lesson.
create or replace function internal.assign_tactics_live_group_for_actor(target_session_id uuid, target_profile_id uuid, target_group_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare session core.tactics_live_sessions;
begin
  session := internal.tactics_live_require_host(target_session_id);
  if not internal.tactics_live_is_open(session) then raise insufficient_privilege using message = 'not_found'; end if;
  if not exists (select 1 from core.tactics_live_groups where id = target_group_id and session_id = session.id) then
    raise invalid_parameter_value using message = 'invalid_group';
  end if;
  update core.tactics_live_participants set group_id = target_group_id
  where session_id = session.id and profile_id = target_profile_id;
  if not found then raise invalid_parameter_value using message = 'invalid_participant'; end if;
  update core.tactics_live_sessions set last_activity_at = now() where id = session.id;
  perform realtime.send(jsonb_build_object('profileId', target_profile_id, 'groupId', target_group_id),
    'group-assigned', 'tactics-live:' || session.id::text, true);
  return internal.tactics_live_groups_json(session.id);
end;
$$;

-- The host shows one group's copy to everyone, or none (null).
create or replace function internal.show_tactics_live_group_for_actor(target_session_id uuid, target_group_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare session core.tactics_live_sessions;
begin
  session := internal.tactics_live_require_host(target_session_id);
  if not internal.tactics_live_is_open(session) then raise insufficient_privilege using message = 'not_found'; end if;
  if target_group_id is not null
    and not exists (select 1 from core.tactics_live_groups where id = target_group_id and session_id = session.id) then
    raise invalid_parameter_value using message = 'invalid_group';
  end if;
  update core.tactics_live_sessions set shown_group = target_group_id, last_activity_at = now() where id = session.id;
  perform realtime.send(jsonb_build_object('groupId', target_group_id), 'group-shown', 'tactics-live:' || session.id::text, true);
end;
$$;

-- The group shown to everyone, with its copy, for anyone in the lesson. Null when none is shown.
create or replace function internal.get_tactics_live_shown_group_for_actor(target_session_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  session core.tactics_live_sessions;
  shown core.tactics_live_groups;
begin
  session := internal.tactics_live_member_session(target_session_id);
  if session.shown_group is null then return null; end if;
  select item.* into shown from core.tactics_live_groups item where item.id = session.shown_group;
  if shown.id is null then return null; end if;
  return internal.tactics_live_group_full(shown);
end;
$$;

-- As in step 1. While the group is shown to everyone, the move also goes out on the lesson's channel.
create or replace function internal.move_tactics_live_group_for_actor(
  target_session_id uuid, target_frame_index integer, object_moves jsonb, dropped boolean
) returns void language plpgsql security definer set search_path = '' as $$
declare
  session core.tactics_live_sessions;
  mine core.tactics_live_groups;
  clean jsonb;
  move jsonb;
  frame_key text := target_frame_index::text;
begin
  session := internal.tactics_live_member_session(target_session_id);
  select item.* into mine from core.tactics_live_groups item
  join core.tactics_live_participants participant on participant.group_id = item.id
  where participant.session_id = session.id and participant.profile_id = auth.uid();
  if mine.id is null then raise insufficient_privilege using message = 'no_group'; end if;
  if jsonb_typeof(object_moves) is distinct from 'object' or (select count(*) from jsonb_object_keys(object_moves)) not between 1 and 40
    or exists (select 1 from jsonb_each(object_moves) item
               where jsonb_typeof(item.value -> 'x') is distinct from 'number' or jsonb_typeof(item.value -> 'y') is distinct from 'number'
                  or (item.value ->> 'x')::numeric not between -60 and 170 or (item.value ->> 'y')::numeric not between -60 and 130
                  or length(item.key) > 80)
    or coalesce(target_frame_index, -1) not between 0 and 500 then
    raise invalid_parameter_value using message = 'invalid_move';
  end if;
  select jsonb_object_agg(item.key, jsonb_build_object('x', item.value -> 'x', 'y', item.value -> 'y')) into clean
  from jsonb_each(object_moves) item;
  if coalesce(dropped, false) then
    update core.tactics_live_groups
    set moves = moves || jsonb_build_object(frame_key, coalesce(moves -> frame_key, '{}'::jsonb) || clean), updated_at = now()
    where id = mine.id;
    update core.tactics_live_sessions set last_activity_at = now()
    where id = session.id and status = 'live' and last_activity_at < now() - interval '10 seconds';
  end if;
  move := jsonb_build_object('groupId', mine.id, 'boardId', mine.board_id, 'frameIndex', target_frame_index, 'moves', clean,
    'dropped', coalesce(dropped, false), 'by', auth.uid());
  perform realtime.send(move, 'group-move', 'tactics-live-group:' || mine.id::text, true);
  if session.shown_group is not distinct from mine.id then
    perform realtime.send(move, 'shown-move', 'tactics-live:' || session.id::text, true);
  end if;
end;
$$;

create or replace function api.assign_tactics_live_group(target_session_id uuid, target_profile_id uuid, target_group_id uuid) returns jsonb
language sql security invoker set search_path = '' as $$ select internal.assign_tactics_live_group_for_actor(target_session_id, target_profile_id, target_group_id) $$;
create or replace function api.show_tactics_live_group(target_session_id uuid, target_group_id uuid) returns void
language sql security invoker set search_path = '' as $$ select internal.show_tactics_live_group_for_actor(target_session_id, target_group_id) $$;
create or replace function api.get_tactics_live_shown_group(target_session_id uuid) returns jsonb
language sql security invoker set search_path = '' as $$ select internal.get_tactics_live_shown_group_for_actor(target_session_id) $$;

revoke all on function
  internal.tactics_live_group_full(core.tactics_live_groups),
  internal.assign_tactics_live_group_for_actor(uuid, uuid, uuid), internal.show_tactics_live_group_for_actor(uuid, uuid),
  internal.get_tactics_live_shown_group_for_actor(uuid),
  api.assign_tactics_live_group(uuid, uuid, uuid), api.show_tactics_live_group(uuid, uuid), api.get_tactics_live_shown_group(uuid)
from public, anon, authenticated;
grant execute on function
  internal.tactics_live_group_full(core.tactics_live_groups),
  internal.assign_tactics_live_group_for_actor(uuid, uuid, uuid), internal.show_tactics_live_group_for_actor(uuid, uuid),
  internal.get_tactics_live_shown_group_for_actor(uuid),
  api.assign_tactics_live_group(uuid, uuid, uuid), api.show_tactics_live_group(uuid, uuid), api.get_tactics_live_shown_group(uuid)
to authenticated;
