-- A board on the match plan shows a small picture of itself
-- (docs/implementation/tacticsboard-teamzone-link.md, step 4).
--
-- Each board in match_plan_json carries a preview: the board's view, its
-- teams' colours and its first frame's objects, for the app to draw as
-- the shared link's chat picture is drawn (webtools/lib/tactics/preview.ts).
-- A whole project shows its first board. A board since removed from its
-- project has no preview.

-- The preview of a board in a project's document: the named one, or the first.
create or replace function internal.tactics_board_preview(document jsonb, target_board_id text)
returns jsonb language sql immutable set search_path = '' as $$
  select jsonb_build_object('view', board->'view', 'teams', board->'teams', 'objects', coalesce(board->'frames'->0->'objects', '[]'::jsonb))
  from jsonb_array_elements(case when jsonb_typeof(document->'boards') = 'array' then document->'boards' else '[]'::jsonb end)
    with ordinality as item(board, place)
  where target_board_id is null or board->>'id' = target_board_id
  order by place
  limit 1
$$;
revoke all on function internal.tactics_board_preview(jsonb, text) from public, anon, authenticated;

-- The plan as in 20270104090000, its boards now with their previews.
create or replace function internal.match_plan_json(event_row core.events, can_edit boolean)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare plan core.match_plans;
begin
  select * into plan from core.match_plans where event_id = event_row.id;
  if not can_edit and (plan.event_id is null or not plan.published) then return null; end if;
  return jsonb_build_object(
    'event_id', event_row.id, 'can_edit', can_edit,
    'opponent_name', event_row.opponent_name, 'home_away', event_row.home_away, 'starts_at', event_row.starts_at,
    'published', coalesce(plan.published, false), 'revision', coalesce(plan.revision, 0), 'updated_at', plan.updated_at,
    'sections', jsonb_build_object(
      'tactics', case when can_edit or plan.tactics_visible
        then jsonb_build_object('text', coalesce(plan.tactics_notes, ''), 'visible', coalesce(plan.tactics_visible, true)) end,
      'set_pieces', case when can_edit or plan.set_pieces_visible
        then jsonb_build_object('text', coalesce(plan.set_pieces_notes, ''), 'visible', coalesce(plan.set_pieces_visible, true)) end,
      'opponent', case when can_edit or plan.opponent_visible
        then jsonb_build_object('text', coalesce(plan.key_opponents_notes, ''), 'visible', coalesce(plan.opponent_visible, false)) end
    ),
    'links', coalesce((
      select jsonb_agg(jsonb_build_object('id', link.id, 'title', link.title, 'url', link.url, 'visible', link.visible_to_players)
        order by link.position, link.created_at)
      from core.module_attachments link
      where link.owner_kind = 'match_plan' and link.owner_id = event_row.id and link.kind = 'link'
        and (can_edit or link.visible_to_players)
    ), '[]'::jsonb),
    'boards', coalesce((
      select jsonb_agg(jsonb_build_object('id', board.id, 'title', board.title, 'visible', board.visible_to_players,
          'project_id', board.project_id, 'board_id', board.board_id,
          'preview', internal.tactics_board_preview(project.document, board.board_id))
        order by board.position, board.created_at)
      from core.module_attachments board
      left join core.tactics_projects project on project.id = board.project_id
      where board.owner_kind = 'match_plan' and board.owner_id = event_row.id and board.kind = 'tactics'
        and (can_edit or board.visible_to_players)
    ), '[]'::jsonb)
  );
end;
$$;
