-- Länkad tavla som inte finns längre (2026-11-15): a linked board whose
-- project or library item was deleted, or whose board was removed from it,
-- comes with missing = true, so the app can say so instead of showing a
-- link that no longer opens. A copy saved in Tacticsboard has a new id, so
-- removing the original leaves its links behind.

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
          'preview', preview.board, 'missing', preview.board is null) end
      ) order by block.position)
      from core.training_blocks block
      cross join lateral (select internal.training_board_preview(block.board_source, block.board_ref, block.board_id) board) preview
      where block.event_id = event_row.id), '[]'::jsonb)
  );
end;
$$;

notify pgrst, 'reload schema';
