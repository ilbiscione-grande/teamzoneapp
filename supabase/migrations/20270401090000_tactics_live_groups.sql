-- Webtools Tacticsboard, live lessons: group work, step 1 of
-- docs/implementation/tacticsboard-live-groups.md. The host splits the
-- participants into groups. Each group gets its own copy of the board in
-- hand, a sandbox: the host's project is not touched. Everyone in a group
-- moves objects on the group's copy. When the host ends the group work, the
-- groups and everything in them are deleted and everyone follows the host
-- again.
--
-- A group keeps the board as it was when the work started, plus where each
-- moved object stands now, per frame. Moves are merged here, so two people
-- dropping at once do not overwrite each other. A group's moves go out on
-- its own private channel "tactics-live-group:<group>". Only the database
-- sends on it; the group's members and the host listen.

create table core.tactics_live_groups (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references core.tactics_live_sessions(id) on delete cascade,
  number integer not null check (number between 1 and 6),
  board_id text not null check (length(board_id) between 1 and 80),
  frame_index integer not null check (frame_index between 0 and 500),
  board jsonb not null,
  -- {"<frame index>": {"<object id>": {"x": .., "y": ..}}}
  moves jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (session_id, number)
);
alter table core.tactics_live_groups enable row level security;
revoke all on core.tactics_live_groups from public, anon, authenticated;

alter table core.tactics_live_participants
  add column group_id uuid references core.tactics_live_groups(id) on delete set null;

-- A sandbox is not kept: a lesson that ends takes its groups with it.
create or replace function internal.tactics_live_drop_groups_on_end()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  delete from core.tactics_live_groups where session_id = new.id;
  return new;
end;
$$;
create trigger tactics_live_sessions_drop_groups after update of status on core.tactics_live_sessions
  for each row when (new.status = 'ended') execute function internal.tactics_live_drop_groups_on_end();

create or replace function internal.tactics_live_group_members(target_group_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('profile_id', participant.profile_id, 'name', participant.display_name)
    order by participant.display_name), '[]'::jsonb)
  from core.tactics_live_participants participant where participant.group_id = target_group_id
$$;

-- A group as the host lists it: without the board, which the host has.
create or replace function internal.tactics_live_group_summary(target core.tactics_live_groups)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', target.id, 'number', target.number, 'board_id', target.board_id,
    'frame_index', target.frame_index, 'members', internal.tactics_live_group_members(target.id))
$$;

create or replace function internal.tactics_live_groups_json(target_session_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(internal.tactics_live_group_summary(item) order by item.number), '[]'::jsonb)
  from core.tactics_live_groups item where item.session_id = target_session_id
$$;

-- The host starts group work on the board and frame in hand. The board is
-- sent as the host's editor has it, so unsaved changes come along.
-- Participants are shared out at random; groups that are already running
-- are replaced. The floor goes back to the host.
create or replace function internal.start_tactics_live_groups_for_actor(
  target_session_id uuid, group_count integer, target_board jsonb, target_frame_index integer
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare session core.tactics_live_sessions;
begin
  session := internal.tactics_live_require_host(target_session_id);
  if not internal.tactics_live_is_open(session) then raise insufficient_privilege using message = 'not_found'; end if;
  if coalesce(group_count, 0) not between 2 and 6 then raise invalid_parameter_value using message = 'invalid_group_count'; end if;
  if jsonb_typeof(target_board) is distinct from 'object' or length(coalesce(target_board ->> 'id', '')) not between 1 and 80
    or jsonb_typeof(target_board -> 'frames') is distinct from 'array'
    or coalesce(target_frame_index, -1) not between 0 and least(500, jsonb_array_length(target_board -> 'frames') - 1)
    or length(target_board::text) > 500000 then
    raise invalid_parameter_value using message = 'invalid_board';
  end if;
  -- Groups left in this host's lessons that ended by themselves (30 idle minutes) go too.
  delete from core.tactics_live_groups item using core.tactics_live_sessions other
  where other.id = item.session_id and other.host_id = auth.uid() and not internal.tactics_live_is_open(other);
  delete from core.tactics_live_groups where session_id = session.id;
  insert into core.tactics_live_groups (session_id, number, board_id, frame_index, board)
  select session.id, number, target_board ->> 'id', target_frame_index, target_board from generate_series(1, group_count) number;
  update core.tactics_live_participants participant set group_id = target.id
  from (
    select shuffled.profile_id, (shuffled.place - 1) % group_count + 1 as number
    from (select profile_id, row_number() over (order by random()) as place
          from core.tactics_live_participants where session_id = session.id) shuffled
  ) placed
  join core.tactics_live_groups target on target.session_id = session.id and target.number = placed.number
  where participant.session_id = session.id and participant.profile_id = placed.profile_id;
  update core.tactics_live_sessions set floor_holder = null, last_activity_at = now() where id = session.id returning * into session;
  perform realtime.send(jsonb_build_object('profileId', null, 'name', null), 'floor', 'tactics-live:' || session.id::text, true);
  perform realtime.send(jsonb_build_object('active', true), 'groups', 'tactics-live:' || session.id::text, true);
  return internal.tactics_live_groups_json(session.id);
end;
$$;

-- The host's list of groups and who is in each (empty when there is no group work).
create or replace function internal.list_tactics_live_groups_for_actor(target_session_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare session core.tactics_live_sessions;
begin
  session := internal.tactics_live_require_host(target_session_id);
  return internal.tactics_live_groups_json(session.id);
end;
$$;

-- The host ends the group work: the groups and their moves are deleted.
create or replace function internal.end_tactics_live_groups_for_actor(target_session_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare session core.tactics_live_sessions;
begin
  session := internal.tactics_live_require_host(target_session_id);
  delete from core.tactics_live_groups where session_id = session.id;
  update core.tactics_live_sessions set last_activity_at = now() where id = session.id;
  perform realtime.send(jsonb_build_object('active', false), 'groups', 'tactics-live:' || session.id::text, true);
end;
$$;

-- A participant's own group: the board, the moves so far and who is in it.
-- Someone who comes in while groups work goes to the smallest group. Null
-- when there is no group work.
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
  return internal.tactics_live_group_summary(mine) || jsonb_build_object('board', mine.board, 'moves', mine.moves);
end;
$$;

-- Someone in a group moves objects on the group's copy: where each is now,
-- and whether they were dropped there (then it is kept).
create or replace function internal.move_tactics_live_group_for_actor(
  target_session_id uuid, target_frame_index integer, object_moves jsonb, dropped boolean
) returns void language plpgsql security definer set search_path = '' as $$
declare
  session core.tactics_live_sessions;
  mine core.tactics_live_groups;
  clean jsonb;
  frame_key text := target_frame_index::text;
begin
  session := internal.tactics_live_member_session(target_session_id);
  select item.* into mine from core.tactics_live_groups item
  join core.tactics_live_participants participant on participant.group_id = item.id
  where participant.session_id = session.id and participant.profile_id = auth.uid();
  if mine.id is null then raise insufficient_privilege using message = 'no_group'; end if;
  if jsonb_typeof(object_moves) is distinct from 'object' or (select count(*) from jsonb_object_keys(object_moves)) not between 1 and 40
    or exists (select 1 from jsonb_each(object_moves) move
               where jsonb_typeof(move.value -> 'x') is distinct from 'number' or jsonb_typeof(move.value -> 'y') is distinct from 'number'
                  or (move.value ->> 'x')::numeric not between -60 and 170 or (move.value ->> 'y')::numeric not between -60 and 130
                  or length(move.key) > 80)
    or coalesce(target_frame_index, -1) not between 0 and 500 then
    raise invalid_parameter_value using message = 'invalid_move';
  end if;
  select jsonb_object_agg(move.key, jsonb_build_object('x', move.value -> 'x', 'y', move.value -> 'y')) into clean
  from jsonb_each(object_moves) move;
  if coalesce(dropped, false) then
    update core.tactics_live_groups
    set moves = moves || jsonb_build_object(frame_key, coalesce(moves -> frame_key, '{}'::jsonb) || clean), updated_at = now()
    where id = mine.id;
    update core.tactics_live_sessions set last_activity_at = now()
    where id = session.id and status = 'live' and last_activity_at < now() - interval '10 seconds';
  end if;
  perform realtime.send(jsonb_build_object('boardId', mine.board_id, 'frameIndex', target_frame_index, 'moves', clean,
    'dropped', coalesce(dropped, false), 'by', auth.uid()), 'group-move', 'tactics-live-group:' || mine.id::text, true);
end;
$$;

-- Who may listen to a group's channel: its members and the lesson's host.
create or replace function internal.tactics_live_group_topic_open(topic text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((
    select internal.tactics_live_is_open(session) and (
      session.host_id = auth.uid()
      or exists (select 1 from core.tactics_live_participants participant
                 where participant.group_id = item.id and participant.profile_id = auth.uid())
    )
    from core.tactics_live_groups item
    join core.tactics_live_sessions session on session.id = item.session_id
    where topic ~ '^tactics-live-group:[0-9a-fA-F-]{36}$'
      and item.id = substring(topic from '^tactics-live-group:([0-9a-fA-F-]{36})$')::uuid
  ), false)
$$;

create policy teamzone_tactics_live_group_select on realtime.messages for select to authenticated using (
  realtime.messages.extension = 'broadcast'
  and (select realtime.topic()) like 'tactics-live-group:%'
  and internal.tactics_live_group_topic_open((select realtime.topic()))
);

create or replace function api.start_tactics_live_groups(target_session_id uuid, group_count integer, target_board jsonb, target_frame_index integer) returns jsonb
language sql security invoker set search_path = '' as $$ select internal.start_tactics_live_groups_for_actor(target_session_id, group_count, target_board, target_frame_index) $$;
create or replace function api.list_tactics_live_groups(target_session_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.list_tactics_live_groups_for_actor(target_session_id) $$;
create or replace function api.end_tactics_live_groups(target_session_id uuid) returns void
language sql security invoker set search_path = '' as $$ select internal.end_tactics_live_groups_for_actor(target_session_id) $$;
create or replace function api.get_tactics_live_group(target_session_id uuid) returns jsonb
language sql security invoker set search_path = '' as $$ select internal.get_tactics_live_group_for_actor(target_session_id) $$;
create or replace function api.move_tactics_live_group(target_session_id uuid, target_frame_index integer, object_moves jsonb, dropped boolean) returns void
language sql security invoker set search_path = '' as $$ select internal.move_tactics_live_group_for_actor(target_session_id, target_frame_index, object_moves, dropped) $$;

revoke all on function
  internal.tactics_live_group_members(uuid), internal.tactics_live_group_summary(core.tactics_live_groups),
  internal.tactics_live_groups_json(uuid), internal.start_tactics_live_groups_for_actor(uuid, integer, jsonb, integer),
  internal.list_tactics_live_groups_for_actor(uuid), internal.end_tactics_live_groups_for_actor(uuid),
  internal.get_tactics_live_group_for_actor(uuid), internal.move_tactics_live_group_for_actor(uuid, integer, jsonb, boolean),
  internal.tactics_live_group_topic_open(text),
  api.start_tactics_live_groups(uuid, integer, jsonb, integer), api.list_tactics_live_groups(uuid), api.end_tactics_live_groups(uuid),
  api.get_tactics_live_group(uuid), api.move_tactics_live_group(uuid, integer, jsonb, boolean)
from public, anon, authenticated;
revoke all on function internal.tactics_live_drop_groups_on_end() from public, anon, authenticated;
grant execute on function
  internal.tactics_live_group_members(uuid), internal.tactics_live_group_summary(core.tactics_live_groups),
  internal.tactics_live_groups_json(uuid), internal.start_tactics_live_groups_for_actor(uuid, integer, jsonb, integer),
  internal.list_tactics_live_groups_for_actor(uuid), internal.end_tactics_live_groups_for_actor(uuid),
  internal.get_tactics_live_group_for_actor(uuid), internal.move_tactics_live_group_for_actor(uuid, integer, jsonb, boolean),
  internal.tactics_live_group_topic_open(text),
  api.start_tactics_live_groups(uuid, integer, jsonb, integer), api.list_tactics_live_groups(uuid), api.end_tactics_live_groups(uuid),
  api.get_tactics_live_group(uuid), api.move_tactics_live_group(uuid, integer, jsonb, boolean)
to authenticated;
