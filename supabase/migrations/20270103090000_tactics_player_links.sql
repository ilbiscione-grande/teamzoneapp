-- Tacticsboard: short links for a team's players
-- (docs/implementation/tacticsboard-teamzone-link.md, step 3). A board the
-- leaders show the players in TeamZone (a match plan's or a training's,
-- step 4) opens in the shared view through a link of its own: made for the
-- one who asked, when they asked, and good for six hours, so a link passed
-- on stops soon. Such a link is the asker's, not the owner's: it is not
-- among the owner's links and never handed out in place of one. The checks
-- of who may see the board are the callers' (step 4); this makes the link.

alter table core.tactics_share_links
  add column expires_at timestamptz,
  add column issued_to uuid references core.profiles(id) on delete cascade,
  add constraint tactics_share_links_issued check ((issued_to is null) = (expires_at is null));
create index tactics_share_links_issued on core.tactics_share_links (issued_to, project_id) where issued_to is not null;

-- A link for the signed-in person to the project or one board: the one they
-- were given before while it has an hour left, else a new one for six hours.
-- Their links run out a day ago are cleared on the way.
create or replace function internal.issue_tactics_player_link(target_project_id uuid, target_board_id text)
returns text language plpgsql security definer set search_path = '' as $$
declare existing text; token text;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  if not exists (select 1 from core.tactics_projects where id = target_project_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  delete from core.tactics_share_links
  where issued_to = auth.uid() and expires_at < now() - interval '1 day';
  select link.token into existing from core.tactics_share_links link
  where link.issued_to = auth.uid() and link.project_id = target_project_id
    and link.board_id is not distinct from target_board_id
    and link.revoked_at is null and link.expires_at > now() + interval '1 hour'
  order by link.expires_at desc limit 1;
  if existing is not null then return existing; end if;
  token := substr(replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''), 1, 40);
  insert into core.tactics_share_links (token, project_id, board_id, created_by, issued_to, expires_at)
  values (token, target_project_id, target_board_id, auth.uid(), auth.uid(), now() + interval '6 hours');
  return token;
end;
$$;

-- The owner's links: the owner's own, never one made for a player.
create or replace function internal.create_tactics_share_link_for_actor(target_project_id uuid, target_board_id text)
returns text language plpgsql security definer set search_path = '' as $$
declare existing text; token text;
begin
  perform internal.tactics_require_owner(target_project_id);
  if target_board_id is not null and not exists (select 1 from core.tactics_projects project,
    jsonb_array_elements(project.document->'boards') board
    where project.id = target_project_id and board->>'id' = target_board_id) then
    raise invalid_parameter_value using message = 'not_found';
  end if;
  select link.token into existing from core.tactics_share_links link
  where link.project_id = target_project_id and link.board_id is not distinct from target_board_id
    and link.revoked_at is null and link.issued_to is null
  limit 1;
  if existing is not null then return existing; end if;
  token := substr(replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''), 1, 40);
  insert into core.tactics_share_links (token, project_id, board_id, created_by)
  values (token, target_project_id, target_board_id, auth.uid());
  return token;
end;
$$;

create or replace function internal.list_tactics_share_links_for_actor(target_project_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform internal.tactics_require_owner(target_project_id);
  return coalesce((select jsonb_agg(jsonb_build_object('token', link.token, 'board_id', link.board_id, 'created_at', link.created_at)
    order by link.created_at) from core.tactics_share_links link
    where link.project_id = target_project_id and link.revoked_at is null and link.issued_to is null), '[]'::jsonb);
end;
$$;

-- What a link shows, as 20261227090000; null for an unknown, revoked or run-out link.
create or replace function internal.get_shared_tactics(target_token text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'name', project.name, 'kind', project.kind, 'updated_at', project.updated_at,
    'team_name', (select team.name from core.teams team where team.id = project.teamzone_team_id),
    'board_id', link.board_id,
    'boards', case when link.board_id is null then project.document->'boards'
      else coalesce((select jsonb_agg(board) from jsonb_array_elements(project.document->'boards') board
        where board->>'id' = link.board_id), '[]'::jsonb) end,
    'branding', project.document->'branding'
  )
  from core.tactics_share_links link
  join core.tactics_projects project on project.id = link.project_id
  where link.token = target_token and link.revoked_at is null
    and (link.expires_at is null or link.expires_at > now())
$$;

-- Made for step 4's own checks to call, never by a person directly.
revoke all on function internal.issue_tactics_player_link(uuid, text) from public, anon, authenticated;
