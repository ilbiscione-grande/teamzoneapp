-- Repair 2026-10-27: 20261221090000_training_pass_library failed on the
-- table name core.tactics_share_links, which Tacticsboard's own share links
-- already use, and was rolled back but logged. This runs it again with the
-- table named core.training_pass_links, then puts back the two functions
-- 20261222090000_training_block_boards changed, which the first one would
-- otherwise overwrite. Run once, in one go; nothing to log.

-- The training session as a pass in Tacticsboard's library (decision
-- package 13, TBL-09, and the product owner 2026-10-27): a leader saves a
-- planned session as a pass to use again. The pass is the leader's training
-- project in Tacticsboard, one empty board per exercise to draw on later;
-- saving the same session again updates that project, keeping the boards
-- already drawn (matched by the exercise's name). Saved, it may be shared
-- with the event's club (its library, as from Tacticsboard) and by a link
-- the leader sends to whom they like: anyone who leads in a club with the
-- Training module may open the link and take a copy into their own
-- library. The link shows the pass as last saved; it can be withdrawn. As
-- everything shared, a pass carries no squad or players (TBL-05).
-- In the session, "Från biblioteket" lists your own training projects, your
-- clubs' library and TeamZone's library, passes and single exercises, in
-- one form; what is taken in is copied as blocks with its origin.

alter table core.training_sessions
  add column tactics_project_id uuid references core.tactics_projects(id) on delete set null;
create index training_sessions_tactics_project on core.training_sessions (tactics_project_id);

create table core.training_pass_links (
  token uuid primary key default gen_random_uuid(),
  library_item_id uuid not null unique references core.tactics_library_items(id) on delete cascade,
  owner_id uuid not null references core.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index training_pass_links_owner on core.training_pass_links (owner_id);
alter table core.training_pass_links enable row level security;
revoke all on core.training_pass_links from public, anon, authenticated;
create policy training_pass_links_no_direct_access on core.training_pass_links
  for all to authenticated using (false) with check (false);

-- A board as shared: without its exercise details (kept beside it) and
-- without ties to players or their names, as Tacticsboard's templates.
create or replace function internal.tactics_board_for_template(board jsonb)
returns jsonb language sql immutable set search_path = '' as $$
  select (board - 'exercise') || jsonb_build_object('frames', coalesce((
    select jsonb_agg(frame || jsonb_build_object('objects', coalesce((
        select jsonb_agg(case when object->>'type' = 'player'
          then object || '{"personId": null, "name": null}'::jsonb else object end order by object_position)
        from jsonb_array_elements(case when jsonb_typeof(frame->'objects') = 'array' then frame->'objects' else '[]'::jsonb end)
          with ordinality objects(object, object_position)), '[]'::jsonb)) order by frame_position)
    from jsonb_array_elements(case when jsonb_typeof(board->'frames') = 'array' then board->'frames' else '[]'::jsonb end)
      with ordinality frames(frame, frame_position)), '[]'::jsonb))
$$;

-- A board's exercise details as the library keeps them (snake case); the
-- organisation is the board's description.
create or replace function internal.tactics_board_exercise_json(board jsonb)
returns jsonb language sql immutable set search_path = '' as $$
  select jsonb_build_object(
    'part', case when board->'exercise'->>'part' in ('warmup', 'main', 'finish') then board->'exercise'->>'part' else 'main' end,
    'minutes', case when jsonb_typeof(board->'exercise'->'minutes') = 'number'
      then least(240, greatest(0, round((board->'exercise'->>'minutes')::numeric))) else 15 end,
    'players', case when jsonb_typeof(board->'exercise'->'players') = 'number'
      then to_jsonb(least(60, greatest(1, round((board->'exercise'->>'players')::numeric)))) else 'null'::jsonb end,
    'area', left(coalesce(board->'exercise'->>'area', ''), 40),
    'organisation', left(coalesce(board->>'description', ''), 2000),
    'coaching_points', left(coalesce(board->'exercise'->>'coachingPoints', ''), 2000),
    'phase', case when board->'exercise'->>'phase' in ('scoring', 'preventing_scoring', 'build_up', 'preventing_build_up',
      'counter', 'regaining', 'attacking_play', 'defending') then to_jsonb(board->'exercise'->>'phase') else 'null'::jsonb end,
    'age_classes', case when jsonb_typeof(board->'exercise'->'ageClasses') = 'array' then board->'exercise'->'ageClasses' else '[]'::jsonb end,
    'game_forms', case when jsonb_typeof(board->'exercise'->'gameForms') = 'array' then board->'exercise'->'gameForms' else '[]'::jsonb end
  )
$$;

-- A pass in the one form the app reads: its exercises in order, each with
-- its name and details.
create or replace function internal.training_pass_json(
  pass_source text, pass_id uuid, pass_kind text, pass_title text, pass_details jsonb, pass_document jsonb,
  pass_author text, pass_updated_at timestamptz
) returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'source', pass_source, 'id', pass_id, 'kind', pass_kind, 'title', pass_title,
    'theme', coalesce(pass_details->>'theme', ''), 'goal', coalesce(pass_details->>'goal', ''),
    'author', pass_author, 'updated_at', pass_updated_at,
    'exercises', case when pass_kind = 'exercise'
      then jsonb_build_array(pass_details || jsonb_build_object('title', pass_title))
      else coalesce((
        select jsonb_agg(coalesce(pass_details->'exercises'->(board_position::integer - 1), '{}'::jsonb)
          || jsonb_build_object('title', left(coalesce(nullif(btrim(board->>'name'), ''), pass_title), 120))
          order by board_position)
        from jsonb_array_elements(pass_document->'boards') with ordinality boards(board, board_position)), '[]'::jsonb) end
  )
$$;

-- One of your training projects as a pass.
create or replace function internal.training_pass_from_project(project core.tactics_projects)
returns jsonb language sql stable set search_path = '' as $$
  select internal.training_pass_json('mine', project.id, 'plan', project.name,
    jsonb_build_object('exercises', coalesce((
      select jsonb_agg(internal.tactics_board_exercise_json(board) order by board_position)
      from jsonb_array_elements(project.document->'boards') with ordinality boards(board, board_position)), '[]'::jsonb)),
    project.document, null, project.updated_at)
$$;

-- A shared item as a pass, with its writer.
create or replace function internal.training_pass_from_shared(item core.tactics_shared_items, pass_source text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select internal.training_pass_json(pass_source, item.id, item.kind, item.title, item.details, item.document,
    case when item.owner_id is null then 'TeamZone'
      else coalesce((select nullif(btrim(profile.display_name), '') from core.profiles profile where profile.id = item.owner_id),
        'En tränare') end,
    item.updated_at)
$$;

-- Whether you lead in a club with the Training module: who may open a link.
create or replace function internal.training_pass_actor_may_open()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from internal.tactics_actor_clubs() club
    where internal.module_allows_read(club.club_id, 'module.training'))
$$;

-- Saves the session, as last saved, as your pass: your training project and
-- its published source in the library. With to_club it is shared with the
-- event's club, with_link gives it a link to send.
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
  boards jsonb := '[]'::jsonb;
  used text[] := '{}';
  saved jsonb;
  shared jsonb;
  link uuid;
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
    select value into old_board from jsonb_array_elements(old_boards)
    where value->>'name' = block.title and not coalesce(value->>'id' = any(used), false) limit 1;
    if old_board is null then
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

-- What the session is saved as for you: your pass, when you saved it,
-- whether it is shared with a club, and its link. Null when you have not
-- saved it.
create or replace function internal.get_training_pass_state_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare event_row core.events; result jsonb;
begin
  event_row := internal.training_session_event(target_event_id);
  if not internal.training_session_can_edit(event_row) then raise insufficient_privilege using message = 'not_allowed'; end if;
  select jsonb_build_object(
    'project_id', project.id, 'title', project.name, 'updated_at', project.updated_at,
    'version', item.version,
    'club_name', (select club.name from core.tactics_shared_items shared join core.clubs club on club.id = shared.club_id
      where shared.library_item_id = item.id),
    'link', (select link.token from core.training_pass_links link where link.library_item_id = item.id)
  ) into result
  from core.training_sessions session
  join core.tactics_projects project on project.id = session.tactics_project_id and project.owner_id = auth.uid()
  left join core.tactics_library_items item on item.source_project_id = project.id and item.owner_id = auth.uid()
    and item.kind = 'plan'
  where session.event_id = event_row.id;
  return result;
end;
$$;

-- Withdraws the session's pass link; the link stops working.
create or replace function internal.delete_training_pass_link_for_actor(target_event_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare event_row core.events;
begin
  event_row := internal.training_session_event(target_event_id);
  if not internal.training_session_can_edit(event_row) then raise insufficient_privilege using message = 'not_allowed'; end if;
  delete from core.training_pass_links link
  using core.training_sessions session, core.tactics_library_items item
  where session.event_id = event_row.id and item.source_project_id = session.tactics_project_id
    and item.owner_id = auth.uid() and link.library_item_id = item.id;
  return internal.get_training_pass_state_for_actor(event_row.id);
end;
$$;

-- The passes and exercises to take into a session: your training projects
-- ('mine'), your clubs' library ('club') or TeamZone's library
-- ('teamzone'); words in the name or theme. Newest first, at most 50.
create or replace function internal.list_training_passes_for_actor(pass_source text, search_text text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare words text[];
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  if pass_source is null or pass_source not in ('mine', 'club', 'teamzone') or length(coalesce(search_text, '')) > 100 then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  words := array_remove(regexp_split_to_array(lower(btrim(coalesce(search_text, ''))), '\s+'), '');
  if pass_source = 'mine' then
    return coalesce((
      select jsonb_agg(internal.training_pass_from_project(hit) order by hit.updated_at desc)
      from (
        select project.* from core.tactics_projects project
        where project.owner_id = auth.uid() and project.kind = 'training'
          and jsonb_array_length(case when jsonb_typeof(project.document->'boards') = 'array'
            then project.document->'boards' else '[]'::jsonb end) > 0
          and not exists (select 1 from unnest(words) word where position(word in lower(project.name)) = 0)
        order by project.updated_at desc limit 50
      ) hit
    ), '[]'::jsonb);
  end if;
  return coalesce((
    select jsonb_agg(internal.training_pass_from_shared(hit, pass_source) order by hit.owner_id is null, hit.updated_at desc)
    from (
      select item.* from core.tactics_shared_items item
      where item.kind in ('plan', 'exercise') and internal.tactics_shared_visible(item)
        and case when pass_source = 'teamzone' then item.club_id is null
          else exists (select 1 from internal.tactics_actor_clubs() club
            where club.club_id = item.club_id or exists (select 1 from core.tactics_club_picks pick
              where pick.club_id = club.club_id and pick.shared_item_id = item.id)) end
        and not exists (select 1 from unnest(words) word
          where position(word in lower(item.title || ' ' || coalesce(item.details->>'theme', ''))) = 0)
      order by item.owner_id is null, item.updated_at desc limit 50
    ) hit
  ), '[]'::jsonb);
end;
$$;

-- The pass behind a link, for one who leads in a club with the Training
-- module.
create or replace function internal.training_pass_link_item(link_token uuid)
returns core.tactics_library_items language plpgsql stable security definer set search_path = '' as $$
declare item core.tactics_library_items;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  select library.* into item from core.training_pass_links link
  join core.tactics_library_items library on library.id = link.library_item_id
  where link.token = link_token;
  if item.id is null or not internal.training_pass_actor_may_open() then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return item;
end;
$$;

create or replace function internal.get_training_pass_link_for_actor(link_token uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare item core.tactics_library_items;
begin
  item := internal.training_pass_link_item(link_token);
  return internal.training_pass_json('link', link_token, item.kind, item.title, item.details, item.document,
    coalesce((select nullif(btrim(profile.display_name), '') from core.profiles profile where profile.id = item.owner_id),
      'En tränare'), item.updated_at)
    || jsonb_build_object('mine', item.owner_id = auth.uid());
end;
$$;

-- Takes a copy of the pass behind a link into your library: a new training
-- project with its boards and exercise details. Returns it as a pass.
create or replace function internal.copy_training_pass_link_for_actor(link_token uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare item core.tactics_library_items; project core.tactics_projects;
begin
  item := internal.training_pass_link_item(link_token);
  insert into core.tactics_projects (owner_id, name, kind, document)
  values (auth.uid(), item.title, case when item.kind = 'lesson' then 'education' else 'training' end,
    jsonb_build_object('schemaVersion', 1, 'squad', '[]'::jsonb, 'boards', coalesce((
      select jsonb_agg(board || jsonb_build_object('id', gen_random_uuid()::text)
        || case when item.kind = 'lesson' then '{}'::jsonb else jsonb_build_object(
          'description', coalesce(exercise->>'organisation', ''),
          'exercise', jsonb_build_object('part', coalesce(exercise->>'part', 'main'),
            'minutes', coalesce(exercise->'minutes', '15'::jsonb), 'players', coalesce(exercise->'players', 'null'::jsonb),
            'area', coalesce(exercise->>'area', ''), 'coachingPoints', coalesce(exercise->>'coaching_points', ''),
            'phase', coalesce(exercise->'phase', 'null'::jsonb), 'ageClasses', coalesce(exercise->'age_classes', '[]'::jsonb),
            'gameForms', coalesce(exercise->'game_forms', '[]'::jsonb))) end
        order by board_position)
      from jsonb_array_elements(item.document->'boards') with ordinality boards(board, board_position)
      cross join lateral (select case when item.kind = 'exercise' then item.details
        else coalesce(item.details->'exercises'->(board_position::integer - 1), '{}'::jsonb) end as exercise) details
    ), '[]'::jsonb)))
  returning * into project;
  return internal.training_pass_from_project(project);
end;
$$;

create or replace function api.save_training_pass(target_event_id uuid, pass_title text, to_club boolean,
  with_link boolean) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.save_training_pass_for_actor(target_event_id, pass_title, to_club, with_link) $$;
create or replace function api.get_training_pass_state(target_event_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$
  select internal.get_training_pass_state_for_actor(target_event_id) $$;
create or replace function api.delete_training_pass_link(target_event_id uuid) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.delete_training_pass_link_for_actor(target_event_id) $$;
create or replace function api.list_training_passes(pass_source text, search_text text) returns jsonb
language sql stable security invoker set search_path = '' as $$
  select internal.list_training_passes_for_actor(pass_source, search_text) $$;
create or replace function api.get_training_pass_link(link_token uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$
  select internal.get_training_pass_link_for_actor(link_token) $$;
create or replace function api.copy_training_pass_link(link_token uuid) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.copy_training_pass_link_for_actor(link_token) $$;

revoke all on function
  internal.tactics_board_for_template(jsonb), internal.tactics_board_exercise_json(jsonb),
  internal.training_pass_json(text, uuid, text, text, jsonb, jsonb, text, timestamptz),
  internal.training_pass_from_project(core.tactics_projects),
  internal.training_pass_from_shared(core.tactics_shared_items, text),
  internal.training_pass_actor_may_open(), internal.training_pass_link_item(uuid),
  internal.save_training_pass_for_actor(uuid, text, boolean, boolean),
  internal.get_training_pass_state_for_actor(uuid), internal.delete_training_pass_link_for_actor(uuid),
  internal.list_training_passes_for_actor(text, text), internal.get_training_pass_link_for_actor(uuid),
  internal.copy_training_pass_link_for_actor(uuid),
  api.save_training_pass(uuid, text, boolean, boolean), api.get_training_pass_state(uuid),
  api.delete_training_pass_link(uuid), api.list_training_passes(text, text), api.get_training_pass_link(uuid),
  api.copy_training_pass_link(uuid)
from public, anon, authenticated;
grant execute on function
  internal.save_training_pass_for_actor(uuid, text, boolean, boolean),
  internal.get_training_pass_state_for_actor(uuid), internal.delete_training_pass_link_for_actor(uuid),
  internal.list_training_passes_for_actor(text, text), internal.get_training_pass_link_for_actor(uuid),
  internal.copy_training_pass_link_for_actor(uuid),
  api.save_training_pass(uuid, text, boolean, boolean), api.get_training_pass_state(uuid),
  api.delete_training_pass_link(uuid), api.list_training_passes(text, text), api.get_training_pass_link(uuid),
  api.copy_training_pass_link(uuid)
to authenticated;
notify pgrst, 'reload schema';

-- From 20261222090000_training_block_boards.
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

notify pgrst, 'reload schema';
