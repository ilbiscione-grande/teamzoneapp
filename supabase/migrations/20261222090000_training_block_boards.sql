-- A board from Tacticsboard's library linked to an exercise in the
-- training session (decision TBL-22). Saving the session as a pass puts the
-- linked board in the pass's project in place of the empty one; a board the
-- leader has drawn on since it was linked is kept until another is linked.
-- Taking a pass from the library links each exercise to its own board.

alter table core.training_blocks
  add column board_source text check (board_source in ('mine', 'club', 'teamzone')),
  add column board_ref uuid,
  add column board_id text check (length(board_id) between 1 and 100),
  add column board_name text not null default '' check (length(board_name) <= 120),
  add constraint training_blocks_board_whole check (
    (board_source is null and board_ref is null and board_id is null)
    or (board_source is not null and board_ref is not null and board_id is not null));

-- Where a pass's board is, to link it; none behind a link, which is copied
-- into your library first.
create or replace function internal.training_pass_board_json(
  pass_source text, pass_id uuid, board jsonb, pass_title text
) returns jsonb language sql immutable set search_path = '' as $$
  select case when pass_source in ('mine', 'club', 'teamzone') and jsonb_typeof(board) = 'object'
    and length(coalesce(board->>'id', '')) between 1 and 100
    then jsonb_build_object('source', pass_source, 'ref', pass_id, 'board_id', board->>'id',
      'name', left(coalesce(nullif(btrim(board->>'name'), ''), pass_title), 120))
    else 'null'::jsonb end
$$;

-- A pass's exercises carry the board each was drawn on, to link it.
create or replace function internal.training_pass_json(
  pass_source text, pass_id uuid, pass_kind text, pass_title text, pass_details jsonb, pass_document jsonb,
  pass_author text, pass_updated_at timestamptz
) returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'source', pass_source, 'id', pass_id, 'kind', pass_kind, 'title', pass_title,
    'theme', coalesce(pass_details->>'theme', ''), 'goal', coalesce(pass_details->>'goal', ''),
    'author', pass_author, 'updated_at', pass_updated_at,
    'exercises', case when pass_kind = 'exercise'
      then jsonb_build_array(pass_details || jsonb_build_object('title', pass_title,
        'board', internal.training_pass_board_json(pass_source, pass_id, pass_document->'boards'->0, pass_title)))
      else coalesce((
        select jsonb_agg(coalesce(pass_details->'exercises'->(board_position::integer - 1), '{}'::jsonb)
          || jsonb_build_object('title', left(coalesce(nullif(btrim(board->>'name'), ''), pass_title), 120),
            'board', internal.training_pass_board_json(pass_source, pass_id, board, pass_title))
          order by board_position)
        from jsonb_array_elements(pass_document->'boards') with ordinality boards(board, board_position)), '[]'::jsonb) end
  )
$$;

-- The linked board as it is now, ready for a project: from your own project
-- or a shared item you can see. Null when it is gone or hidden.
create or replace function internal.training_block_board(block core.training_blocks)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare document jsonb; board jsonb;
begin
  if block.board_source = 'mine' then
    select project.document into document from core.tactics_projects project
    where project.id = block.board_ref and project.owner_id = auth.uid();
  elsif block.board_source in ('club', 'teamzone') then
    select item.document into document from core.tactics_shared_items item
    where item.id = block.board_ref and internal.tactics_shared_visible(item);
  end if;
  select value into board from jsonb_array_elements(
    case when jsonb_typeof(document->'boards') = 'array' then document->'boards' else '[]'::jsonb end)
  where value->>'id' = block.board_id limit 1;
  if board is null then return null; end if;
  return internal.tactics_board_for_template(board)
    || jsonb_build_object('linkedFrom', block.board_source || ':' || block.board_ref || ':' || block.board_id);
end;
$$;

create or replace function internal.training_session_json(event_row core.events, can_edit boolean)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare session core.training_sessions;
begin
  select * into session from core.training_sessions where event_id = event_row.id;
  if not can_edit and (session.event_id is null or not session.published) then return null; end if;
  return jsonb_build_object(
    'event_id', event_row.id, 'can_edit', can_edit,
    'roster_saved', session.roster is not null,
    'roster', internal.training_players_json(internal.training_session_roster(event_row),event_row.club_id),
    'title', event_row.title, 'starts_at', event_row.starts_at, 'ends_at', event_row.ends_at,
    'revision', coalesce(session.revision, 0), 'published', coalesce(session.published, false),
    'theme', coalesce(session.theme, coalesce(event_row.training_theme, '')),
    'goal', coalesce(session.goal, ''),
    'event_plan', case when session.event_id is null then nullif(btrim(coalesce(event_row.training_plan, '')), '') end,
    'updated_at', session.updated_at,
    'updated_by', (select nullif(btrim(profile.display_name), '') from core.profiles profile where profile.id = session.updated_by),
    'blocks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', block.id, 'part', block.part, 'title', block.title, 'minutes', block.minutes,
        'organisation', block.organisation, 'coaching_points', block.coaching_points, 'phase', block.phase,
        'source_kind', block.source_kind, 'source_id', block.source_id, 'players', internal.training_players_json(block.players,event_row.club_id),
        'board', case when block.board_source is not null then jsonb_build_object('source', block.board_source,
          'ref', block.board_ref, 'board_id', block.board_id, 'name', block.board_name) end
      ) order by block.position)
      from core.training_blocks block where block.event_id = event_row.id), '[]'::jsonb)
  );
end;
$$;

-- Saving keeps its checks; the boards are set on the saved blocks after.
alter function internal.save_training_session_roster_for_actor(uuid, bigint, text, text, boolean, jsonb, jsonb)
  rename to save_training_session_blocks_for_actor;

create function internal.save_training_session_roster_for_actor(
  target_event_id uuid, expected_revision bigint, session_theme text, session_goal text, is_published boolean,
  session_blocks jsonb, session_roster jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare block jsonb; event_row core.events;
begin
  if jsonb_typeof(session_blocks) = 'array' then
    for block in select value from jsonb_array_elements(session_blocks) loop
      if jsonb_typeof(block->'board') = 'object' and (
        coalesce(block->'board'->>'source', '') not in ('mine', 'club', 'teamzone')
        or coalesce(block->'board'->>'ref', '') !~ '^[0-9a-fA-F-]{36}$'
        or length(coalesce(block->'board'->>'board_id', '')) not between 1 and 100
        or length(coalesce(block->'board'->>'name', '')) > 120) then
        raise invalid_parameter_value using message = 'invalid_board';
      end if;
    end loop;
  end if;
  perform internal.save_training_session_blocks_for_actor(target_event_id, expected_revision, session_theme,
    session_goal, is_published, session_blocks, session_roster);
  event_row := internal.training_session_event(target_event_id);
  update core.training_blocks block set
    board_source = entry.value->'board'->>'source',
    board_ref = (entry.value->'board'->>'ref')::uuid,
    board_id = entry.value->'board'->>'board_id',
    board_name = btrim(coalesce(entry.value->'board'->>'name', ''))
  from jsonb_array_elements(session_blocks) with ordinality entry(value, position)
  where block.event_id = event_row.id and block.position = entry.position - 1
    and jsonb_typeof(entry.value->'board') = 'object';
  return internal.training_session_json(event_row, true);
end;
$$;

-- Saving a pass puts each linked board in the project, unless the board
-- there came from the same link (it may have been drawn on since).
create or replace function internal.save_training_pass_for_actor(
  target_event_id uuid, pass_title text, to_club boolean, with_link boolean
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  event_row core.events;
  session core.training_sessions;
  project core.tactics_projects;
  block core.training_blocks;
  old_boards jsonb;
  old_board jsonb;
  linked jsonb;
  boards jsonb := '[]'::jsonb;
  used text[] := '{}';
  saved jsonb;
  shared jsonb;
begin
  event_row := internal.training_session_event(target_event_id);
  if not internal.training_session_can_edit(event_row) then raise insufficient_privilege using message = 'not_allowed'; end if;
  if length(btrim(coalesce(pass_title, ''))) not between 1 and 120 or with_link is null or to_club is null then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  select * into session from core.training_sessions where event_id = event_row.id for update;
  if session.event_id is null or not exists (select 1 from core.training_blocks where event_id = event_row.id) then
    raise invalid_parameter_value using message = 'nothing_to_save';
  end if;
  select * into project from core.tactics_projects
  where id = session.tactics_project_id and owner_id = auth.uid() for update;
  old_boards := case when jsonb_typeof(project.document->'boards') = 'array' then project.document->'boards' else '[]'::jsonb end;
  for block in select * from core.training_blocks where event_id = event_row.id order by position loop
    old_board := null;
    linked := case when block.board_source is not null then internal.training_block_board(block) end;
    select value into old_board from jsonb_array_elements(old_boards)
    where not coalesce(value->>'id' = any(used), false)
      and (value->>'name' = block.title or (linked is not null and value->>'linkedFrom' = linked->>'linkedFrom'))
    order by coalesce(linked is not null and value->>'linkedFrom' = linked->>'linkedFrom', false) desc limit 1;
    if linked is not null and old_board->>'linkedFrom' is distinct from linked->>'linkedFrom' then
      old_board := linked || jsonb_build_object('id', coalesce(old_board->>'id', gen_random_uuid()::text));
    elsif old_board is null then
      old_board := jsonb_build_object('id', gen_random_uuid()::text, 'view', 'full', 'overlay', 'none',
        'showNames', true, 'showPositions', false,
        'frames', jsonb_build_array(jsonb_build_object('id', gen_random_uuid()::text, 'objects', '[]'::jsonb,
          'durationMs', 1500, 'note', '')));
    end if;
    used := used || (old_board->>'id');
    boards := boards || jsonb_build_array(old_board || jsonb_build_object(
      'name', block.title, 'description', block.organisation,
      'exercise', '{"players": null, "area": "", "ageClasses": [], "gameForms": []}'::jsonb
        || coalesce(case when jsonb_typeof(old_board->'exercise') = 'object' then old_board->'exercise' end, '{}'::jsonb)
        || jsonb_build_object('part', block.part, 'minutes', block.minutes, 'coachingPoints', block.coaching_points,
          'phase', block.phase)));
  end loop;
  if project.id is null then
    insert into core.tactics_projects (owner_id, name, kind, document)
    values (auth.uid(), btrim(pass_title), 'training',
      jsonb_build_object('schemaVersion', 1, 'boards', boards, 'squad', '[]'::jsonb))
    returning * into project;
    update core.training_sessions set tactics_project_id = project.id where event_id = event_row.id;
  else
    update core.tactics_projects set name = btrim(pass_title), document = document || jsonb_build_object('boards', boards),
      revision = revision + 1, updated_at = now()
    where id = project.id returning * into project;
  end if;
  saved := internal.save_tactics_library_item_for_actor('plan', btrim(pass_title),
    jsonb_build_object('theme', left(session.theme, 200), 'goal', left(session.goal, 2000),
      'exercises', (select jsonb_agg(internal.tactics_board_exercise_json(board) order by board_position)
        from jsonb_array_elements(boards) with ordinality saved_boards(board, board_position))),
    jsonb_build_object('schemaVersion', 1,
      'boards', (select jsonb_agg(internal.tactics_board_for_template(board) order by board_position)
        from jsonb_array_elements(boards) with ordinality saved_boards(board, board_position))),
    project.id, null);
  if to_club then
    shared := internal.share_tactics_library_item_for_actor((saved->>'id')::uuid, event_row.club_id);
  end if;
  if with_link then
    insert into core.training_pass_links (library_item_id, owner_id) values ((saved->>'id')::uuid, auth.uid())
    on conflict (library_item_id) do nothing;
  end if;
  return internal.get_training_pass_state_for_actor(event_row.id);
end;
$$;

revoke all on function internal.training_pass_board_json(text, uuid, jsonb, text),
  internal.training_block_board(core.training_blocks),
  internal.save_training_session_blocks_for_actor(uuid, bigint, text, text, boolean, jsonb, jsonb),
  internal.save_training_session_roster_for_actor(uuid, bigint, text, text, boolean, jsonb, jsonb)
  from public, anon, authenticated;
grant execute on function internal.save_training_session_roster_for_actor(uuid, bigint, text, text, boolean, jsonb, jsonb) to authenticated;
notify pgrst, 'reload schema';
