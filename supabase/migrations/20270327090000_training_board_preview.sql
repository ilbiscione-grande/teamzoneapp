-- Miniatyr av länkad tavla (2026-11-15): a training session's linked boards
-- come with their first frame in short form, for the app to draw a small
-- picture of the board in the exercise. Only what the picture needs: the
-- view, the crop, the team colours and the objects' places, shapes and
-- colours (no player names). The session's own read rules decide who sees
-- it, so the board is read without the owner's or the library's checks.

create or replace function internal.training_board_preview(board_source text, board_ref uuid, board_key text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare document jsonb; board jsonb;
begin
  if board_source = 'mine' then
    select project.document into document from core.tactics_projects project where project.id = board_ref;
  elsif board_source in ('club', 'teamzone') then
    select item.document into document from core.tactics_shared_items item where item.id = board_ref;
  end if;
  select value into board from jsonb_array_elements(
    case when jsonb_typeof(document->'boards') = 'array' then document->'boards' else '[]'::jsonb end)
  where value->>'id' = board_key limit 1;
  if board is null then return null; end if;
  return jsonb_build_object(
    'view', board->'view',
    'crop', board->'crop',
    'teams', jsonb_build_object(
      'home', jsonb_build_object('color', board#>'{teams,home,color}', 'number_color', board#>'{teams,home,numberColor}'),
      'away', jsonb_build_object('color', board#>'{teams,away,color}', 'number_color', board#>'{teams,away,numberColor}')),
    'objects', coalesce((
      select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'type', item->'type', 'x', item->'x', 'y', item->'y', 'side', item->'side', 'number', item->'number',
        'color', item->'color', 'attached', case when item->>'type' = 'ball' then item->>'attachedTo' is not null end,
        'width', item->'width', 'height', item->'height', 'fill', item->'fill', 'dashed', item->'dashed',
        'rotation', item->'rotation', 'scale', item->'scale', 'points', item->'points', 'arrow', item->'arrow'
      )) order by ordinality)
      from jsonb_array_elements(case when jsonb_typeof(board#>'{frames,0,objects}') = 'array'
        then board#>'{frames,0,objects}' else '[]'::jsonb end) with ordinality as objects(item, ordinality)
      where ordinality <= 80 and coalesce((item->>'hidden')::boolean, false) = false
        and item->>'type' in ('player', 'ball', 'cone', 'pole', 'mannequin', 'goal', 'rect', 'ellipse', 'line')
    ), '[]'::jsonb)
  );
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
          'ref', block.board_ref, 'board_id', block.board_id, 'name', block.board_name,
          'preview', internal.training_board_preview(block.board_source, block.board_ref, block.board_id)) end
      ) order by block.position)
      from core.training_blocks block where block.event_id = event_row.id), '[]'::jsonb)
  );
end;
$$;

revoke all on function internal.training_board_preview(text, uuid, text) from public, anon, authenticated;

notify pgrst, 'reload schema';
