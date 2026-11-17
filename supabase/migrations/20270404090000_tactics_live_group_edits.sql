-- Webtools Tacticsboard, live lessons: group work, step 4 of
-- docs/implementation/tacticsboard-live-groups.md. Full editing in the
-- groups: everyone in a group places, changes and removes players, lines,
-- areas and the rest on the group's copy, with the editor's own tools.
--
-- A change is sent per object. Each object is sent whole as it now stands,
-- or as removed. The group keeps them per frame in "edits", after the
-- starting board:
--   {"<frame>": {"<object id>": {...object...} | null}}
-- Moves (step 1) still go out while something is dragged. A later edit of
-- the same object replaces its move, so the newest of the two always
-- stands. Two people changing different objects at once both stand. The
-- same object changed by two people at once: the latest one wins, as with
-- moves.

alter table core.tactics_live_groups add column edits jsonb not null default '{}'::jsonb;

-- A group with its board, moves, edits, drawing, chat and time left.
create or replace function internal.tactics_live_group_full(target core.tactics_live_groups)
returns jsonb language sql stable security definer set search_path = '' as $$
  select internal.tactics_live_group_summary(target) || jsonb_build_object(
    'board', target.board, 'moves', target.moves, 'edits', target.edits,
    'strokes', coalesce((select jsonb_agg(internal.tactics_live_stroke_json(stroke) order by stroke.created_at)
      from core.tactics_live_strokes stroke where stroke.group_id = target.id), '[]'::jsonb),
    'messages', coalesce((select jsonb_agg(internal.tactics_live_message_json(m) order by m.created_at) from (
      select * from core.tactics_live_messages message where message.group_id = target.id and message.deleted_at is null
      order by message.created_at desc limit 200) m), '[]'::jsonb),
    'ends_in', internal.tactics_live_groups_ends_in(target.session_id))
$$;

-- Someone in a group changes objects on one frame of the group's copy:
-- objects as they now stand, by id, and the ids of objects removed.
create or replace function internal.edit_tactics_live_group_for_actor(
  target_session_id uuid, target_frame_index integer, changed_objects jsonb, removed_ids jsonb
) returns void language plpgsql security definer set search_path = '' as $$
declare
  session core.tactics_live_sessions;
  mine core.tactics_live_groups;
  changed jsonb := coalesce(changed_objects, '{}'::jsonb);
  removed jsonb := coalesce(removed_ids, '[]'::jsonb);
  frame_key text := target_frame_index::text;
  ids text[];
  payload jsonb;
begin
  session := internal.tactics_live_member_session(target_session_id);
  mine := internal.tactics_live_own_group(session);
  if jsonb_typeof(changed) is distinct from 'object' or jsonb_typeof(removed) is distinct from 'array'
    or (select count(*) from jsonb_object_keys(changed)) + jsonb_array_length(removed) not between 1 and 60
    or coalesce(target_frame_index, -1) not between 0 and least(500, jsonb_array_length(mine.board -> 'frames') - 1)
    or exists (select 1 from jsonb_each(changed) item
               where jsonb_typeof(item.value) is distinct from 'object' or item.value ->> 'id' is distinct from item.key
                  or length(item.key) not between 1 and 80
                  or length(coalesce(item.value ->> 'type', '')) not between 1 and 30
                  or jsonb_typeof(item.value -> 'x') is distinct from 'number' or jsonb_typeof(item.value -> 'y') is distinct from 'number'
                  or length(item.value::text) > 20000)
    or exists (select 1 from jsonb_array_elements(removed) item
               where jsonb_typeof(item) is distinct from 'string' or length(item #>> '{}') not between 1 and 80) then
    raise invalid_parameter_value using message = 'invalid_edit';
  end if;
  select array_agg(key) into ids from (
    select jsonb_object_keys(changed) as key union select jsonb_array_elements_text(removed)
  ) keys;
  update core.tactics_live_groups
  set edits = edits || jsonb_build_object(frame_key, coalesce(edits -> frame_key, '{}'::jsonb) || changed
        || coalesce((select jsonb_object_agg(item, 'null'::jsonb) from jsonb_array_elements_text(removed) item), '{}'::jsonb)),
      -- An edit is the object as it now stands: an older move of it gives way.
      moves = case when moves ? frame_key then jsonb_set(moves, array[frame_key], (moves -> frame_key) - ids) else moves end,
      updated_at = now()
  where id = mine.id
  returning * into mine;
  if length(mine.edits::text) > 1000000 then raise invalid_parameter_value using message = 'too_large'; end if;
  update core.tactics_live_sessions set last_activity_at = now()
  where id = session.id and status = 'live' and last_activity_at < now() - interval '10 seconds';
  payload := jsonb_build_object('groupId', mine.id, 'frameIndex', target_frame_index, 'objects', changed, 'removed', removed, 'by', auth.uid());
  perform realtime.send(payload, 'group-edit', 'tactics-live-group:' || mine.id::text, true);
  if session.shown_group is not distinct from mine.id then
    perform realtime.send(payload, 'shown-edit', 'tactics-live:' || session.id::text, true);
  end if;
end;
$$;

create or replace function api.edit_tactics_live_group(target_session_id uuid, target_frame_index integer, changed_objects jsonb, removed_ids jsonb) returns void
language sql security invoker set search_path = '' as $$ select internal.edit_tactics_live_group_for_actor(target_session_id, target_frame_index, changed_objects, removed_ids) $$;

revoke all on function
  internal.edit_tactics_live_group_for_actor(uuid, integer, jsonb, jsonb), api.edit_tactics_live_group(uuid, integer, jsonb, jsonb)
from public, anon, authenticated;
grant execute on function
  internal.edit_tactics_live_group_for_actor(uuid, integer, jsonb, jsonb), api.edit_tactics_live_group(uuid, integer, jsonb, jsonb)
to authenticated;
