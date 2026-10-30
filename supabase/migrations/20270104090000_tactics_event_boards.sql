-- Tacticsboard in the match plan and the training
-- (docs/implementation/tacticsboard-teamzone-link.md, step 4).
--
-- The match plan gets boards beside its links: an attachment of kind
-- 'tactics' naming a project and one of its boards, or the whole project.
-- Those preparing the match pick from their own projects and the ones they
-- may open as the team's leaders (20270102090000). The players see the
-- shown ones once the plan is published, as they see links. Like a link, it
-- is shown or not, or removed, with change_match_plan_link.
--
-- A training exercise's board drawn in the leader's own project ('mine')
-- opens for the players of a published session; one from a library is
-- not yet shown to them.
--
-- Opening gives a short link of the one asking's own (20270103090000) to
-- the shared view.

alter table core.module_attachments drop constraint if exists module_attachments_kind_check;
alter table core.module_attachments
  add constraint module_attachments_kind_check check (kind in ('link', 'tactics')),
  add column project_id uuid references core.tactics_projects(id) on delete cascade,
  add column board_id text check (board_id is null or length(board_id) between 1 and 100),
  add constraint module_attachments_tactics check ((kind = 'tactics') = (project_id is not null));

-- The plan with its links and, now, its boards.
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
          'project_id', board.project_id, 'board_id', board.board_id)
        order by board.position, board.created_at)
      from core.module_attachments board
      where board.owner_kind = 'match_plan' and board.owner_id = event_row.id and board.kind = 'tactics'
        and (can_edit or board.visible_to_players)
    ), '[]'::jsonb)
  );
end;
$$;

-- What those preparing the match may put on the plan: their own projects and
-- the ones they open as the team's leaders, the latest first, with their boards.
create or replace function internal.list_match_plan_board_choices_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare event_row core.events;
begin
  event_row := internal.match_plan_event(target_event_id);
  if not internal.match_plan_can_edit(event_row) then raise insufficient_privilege using message = 'not_allowed'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'project_id', project.id, 'name', project.name, 'team_name', (select team.name from core.teams team where team.id = project.teamzone_team_id),
      'mine', project.owner_id = auth.uid(), 'updated_at', project.updated_at,
      'boards', coalesce((select jsonb_agg(jsonb_build_object('id', board->>'id', 'name', coalesce(board->>'name', '')))
        from jsonb_array_elements(case when jsonb_typeof(project.document->'boards') = 'array' then project.document->'boards' else '[]'::jsonb end) board), '[]'::jsonb)
    ) order by project.teamzone_team_id is not distinct from event_row.owning_team_id desc, project.updated_at desc)
    from core.tactics_projects project
    where project.owner_id = auth.uid()
      or project.teamzone_team_id in (select team.team_id from internal.tournament_actor_teams() team)
  ), '[]'::jsonb);
end;
$$;

-- A board (or the whole project) on the plan; at most 30 attachments in all.
create or replace function internal.add_match_plan_board_for_actor(target_event_id uuid, target_project_id uuid, target_board_id text, show_players boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  event_row core.events;
  project core.tactics_projects;
  board_name text;
  added core.module_attachments;
begin
  event_row := internal.match_plan_event(target_event_id);
  if not internal.match_plan_can_edit(event_row) then raise insufficient_privilege using message = 'not_allowed'; end if;
  select * into project from core.tactics_projects where id = target_project_id;
  if internal.tactics_project_access(project) is null then raise insufficient_privilege using message = 'not_found'; end if;
  if target_board_id is not null then
    select board->>'name' into board_name from jsonb_array_elements(
      case when jsonb_typeof(project.document->'boards') = 'array' then project.document->'boards' else '[]'::jsonb end) board
    where board->>'id' = target_board_id limit 1;
    if not found then raise invalid_parameter_value using message = 'not_found'; end if;
  end if;
  if (select count(*) from core.module_attachments where owner_kind = 'match_plan' and owner_id = event_row.id) >= 30 then
    raise check_violation using message = 'too_many_links';
  end if;
  insert into core.module_attachments (club_id, owner_kind, owner_id, kind, title, visible_to_players, position, created_by, project_id, board_id)
  values (event_row.club_id, 'match_plan', event_row.id, 'tactics',
    left(case when target_board_id is null then project.name
      else coalesce(nullif(btrim(board_name), ''), 'Tavla') || ' · ' || project.name end, 120),
    coalesce(show_players, false),
    coalesce((select max(position) + 1 from core.module_attachments where owner_kind = 'match_plan' and owner_id = event_row.id), 0),
    auth.uid(), project.id, target_board_id)
  returning * into added;
  return jsonb_build_object('id', added.id, 'title', added.title, 'visible', added.visible_to_players,
    'project_id', added.project_id, 'board_id', added.board_id);
end;
$$;

-- A board on the plan to watch: for those preparing the match, and for the
-- players a shown board of a published plan. The shared view's path back.
create or replace function internal.open_match_plan_board_for_actor(target_attachment_id uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare
  board core.module_attachments;
  event_row core.events;
begin
  select * into board from core.module_attachments where id = target_attachment_id and owner_kind = 'match_plan' and kind = 'tactics';
  if board.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  event_row := internal.match_plan_event(board.owner_id);
  if not internal.match_plan_can_edit(event_row) and not (board.visible_to_players
    and exists (select 1 from core.match_plans plan where plan.event_id = event_row.id and plan.published)) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return '/delad/' || internal.issue_tactics_player_link(board.project_id, board.board_id);
end;
$$;

-- An exercise's board to watch: for those preparing the training, and for
-- the players of a published session. A board in a library is not shown yet.
create or replace function internal.open_training_block_board_for_actor(target_block_id uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare
  block core.training_blocks;
  event_row core.events;
begin
  select * into block from core.training_blocks where id = target_block_id;
  if block.id is null or block.board_source is null then raise insufficient_privilege using message = 'not_found'; end if;
  event_row := internal.training_session_event(block.event_id);
  if not internal.training_session_can_edit(event_row)
    and not exists (select 1 from core.training_sessions session where session.event_id = event_row.id and session.published) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if block.board_source <> 'mine' then raise feature_not_supported using message = 'library_board'; end if;
  if not exists (select 1 from core.tactics_projects project where project.id = block.board_ref) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return '/delad/' || internal.issue_tactics_player_link(block.board_ref, block.board_id);
end;
$$;

create or replace function api.list_match_plan_board_choices(target_event_id uuid) returns jsonb language sql stable security invoker set search_path = '' as
$$ select internal.list_match_plan_board_choices_for_actor(target_event_id) $$;
create or replace function api.add_match_plan_board(target_event_id uuid, target_project_id uuid, target_board_id text, show_players boolean) returns jsonb
language sql security invoker set search_path = '' as
$$ select internal.add_match_plan_board_for_actor(target_event_id, target_project_id, target_board_id, show_players) $$;
create or replace function api.open_match_plan_board(target_attachment_id uuid) returns text language sql security invoker set search_path = '' as
$$ select internal.open_match_plan_board_for_actor(target_attachment_id) $$;
create or replace function api.open_training_block_board(target_block_id uuid) returns text language sql security invoker set search_path = '' as
$$ select internal.open_training_block_board_for_actor(target_block_id) $$;

revoke all on function
  internal.list_match_plan_board_choices_for_actor(uuid), internal.add_match_plan_board_for_actor(uuid, uuid, text, boolean),
  internal.open_match_plan_board_for_actor(uuid), internal.open_training_block_board_for_actor(uuid),
  api.list_match_plan_board_choices(uuid), api.add_match_plan_board(uuid, uuid, text, boolean),
  api.open_match_plan_board(uuid), api.open_training_block_board(uuid)
from public, anon, authenticated;
grant execute on function
  internal.list_match_plan_board_choices_for_actor(uuid), internal.add_match_plan_board_for_actor(uuid, uuid, text, boolean),
  internal.open_match_plan_board_for_actor(uuid), internal.open_training_block_board_for_actor(uuid),
  api.list_match_plan_board_choices(uuid), api.add_match_plan_board(uuid, uuid, text, boolean),
  api.open_match_plan_board(uuid), api.open_training_block_board(uuid)
to authenticated;
