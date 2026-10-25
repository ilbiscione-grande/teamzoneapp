-- Tacticsboard's library, my library as my projects (the product owner,
-- 2026-10-25): "Mitt bibliotek" is all of your projects, matches,
-- trainings and teaching material alike, filtered as TeamZone's library is
-- (words, kind, the part of the session, the phase of the game, age class
-- and game form, read from the boards' exercise details). There is no
-- separate step of saving in a library: a board is published as an exercise,
-- or a project as a pass or a session, straight to the club or the whole
-- community. Each project shows what is published from it. A published
-- item's source is still kept in core.tactics_library_items, which the
-- shared copy points to.

-- Whether a project's name and boards match the words and filters.
create or replace function internal.tactics_project_matches(
  project core.tactics_projects, words text[], project_kind text, exercise_part text, game_phase text,
  age_class text, game_form text
) returns boolean language sql immutable set search_path = '' as $$
  select (project_kind is null or project.kind = project_kind)
    and (exercise_part is null or exists (select 1 from jsonb_array_elements(project.document->'boards') board
      where board->'exercise'->>'part' = exercise_part))
    and (game_phase is null or exists (select 1 from jsonb_array_elements(project.document->'boards') board
      where board->'exercise'->>'phase' = game_phase))
    and (age_class is null or exists (select 1 from jsonb_array_elements(project.document->'boards') board
      where coalesce(board->'exercise'->'ageClasses', '[]'::jsonb) ? age_class))
    and (game_form is null or exists (select 1 from jsonb_array_elements(project.document->'boards') board
      where coalesce(board->'exercise'->'gameForms', '[]'::jsonb) ? game_form))
    and not exists (select 1 from unnest(coalesce(words, '{}'::text[])) word
      where position(word in lower(project.name || ' ' || coalesce((
        select string_agg(coalesce(board->>'name', '') || ' ' || coalesce(board->>'description', '') || ' '
          || coalesce(board->'exercise'->>'coachingPoints', ''), ' ')
        from jsonb_array_elements(project.document->'boards') board), ''))) = 0)
$$;

-- Your projects, newest first, filtered; each with what is published from it.
create or replace function internal.search_my_tactics_projects_for_actor(
  search_text text, project_kind text, exercise_part text, game_phase text, age_class text, game_form text
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare words text[];
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  if length(coalesce(search_text, '')) > 100 then raise invalid_parameter_value using message = 'invalid_input'; end if;
  words := array_remove(regexp_split_to_array(lower(btrim(coalesce(search_text, ''))), '\s+'), '');
  return coalesce((
    select jsonb_agg(internal.tactics_project_summary(project) || jsonb_build_object(
      'published', coalesce((
        select jsonb_agg(jsonb_build_object(
          'item_id', item.id, 'kind', item.kind, 'title', item.title, 'board_id', item.source_board_id,
          'shared_id', shared.id, 'version', shared.version, 'hidden', shared.hidden,
          'current', shared.updated_at >= item.updated_at, 'club_id', shared.club_id,
          'club_name', (select club.name from core.clubs club where club.id = shared.club_id)
        ) order by item.kind, item.title)
        from core.tactics_library_items item
        join core.tactics_shared_items shared on shared.library_item_id = item.id
        where item.source_project_id = project.id and item.owner_id = auth.uid()), '[]'::jsonb)
    ) order by project.updated_at desc)
    from core.tactics_projects project
    where project.owner_id = auth.uid()
      and internal.tactics_project_matches(project, words, project_kind, exercise_part, game_phase, age_class, game_form)
  ), '[]'::jsonb);
end;
$$;

-- Publishes a board as an exercise or a project as a pass or a session,
-- with the community (target_club_id null) or one of your clubs: kept as
-- the project's published source and shared, in one step. Again, it
-- publishes the latest version and who sees it may change.
create or replace function internal.publish_tactics_item_for_actor(
  item_kind text, item_title text, item_details jsonb, item_document jsonb, from_project_id uuid, from_board_id text,
  target_club_id uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare saved jsonb;
begin
  if from_project_id is null then raise invalid_parameter_value using message = 'invalid_input'; end if;
  saved := internal.save_tactics_library_item_for_actor(item_kind, item_title, item_details, item_document,
    from_project_id, from_board_id);
  return internal.share_tactics_library_item_for_actor((saved->>'id')::uuid, target_club_id);
end;
$$;

create or replace function api.search_my_tactics_projects(search_text text, project_kind text, exercise_part text,
  game_phase text, age_class text, game_form text) returns jsonb
language sql stable security invoker set search_path = '' as $$
  select internal.search_my_tactics_projects_for_actor(search_text, project_kind, exercise_part, game_phase, age_class, game_form) $$;
create or replace function api.publish_tactics_item(item_kind text, item_title text, item_details jsonb, item_document jsonb,
  from_project_id uuid, from_board_id text, target_club_id uuid) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.publish_tactics_item_for_actor(item_kind, item_title, item_details, item_document, from_project_id,
    from_board_id, target_club_id) $$;

revoke all on function
  internal.tactics_project_matches(core.tactics_projects, text[], text, text, text, text, text),
  internal.search_my_tactics_projects_for_actor(text, text, text, text, text, text),
  internal.publish_tactics_item_for_actor(text, text, jsonb, jsonb, uuid, text, uuid),
  api.search_my_tactics_projects(text, text, text, text, text, text),
  api.publish_tactics_item(text, text, jsonb, jsonb, uuid, text, uuid)
from public, anon, authenticated;
grant execute on function
  internal.search_my_tactics_projects_for_actor(text, text, text, text, text, text),
  internal.publish_tactics_item_for_actor(text, text, jsonb, jsonb, uuid, text, uuid),
  api.search_my_tactics_projects(text, text, text, text, text, text),
  api.publish_tactics_item(text, text, jsonb, jsonb, uuid, text, uuid)
to authenticated;
notify pgrst, 'reload schema';
