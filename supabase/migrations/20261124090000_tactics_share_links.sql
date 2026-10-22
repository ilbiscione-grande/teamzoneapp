-- Webtools Tacticsboard: share links. The owner makes a link to the whole
-- project or one board; anyone with it watches and plays the boards without
-- an account, always as last saved. A link is a long random token kept as
-- it is, so the owner can copy it again; it stops when revoked. The page is
-- read by Webtools' server only (as the public tournament page).

create table core.tactics_share_links (
  token text primary key check (token ~ '^[0-9a-f]{40}$'),
  project_id uuid not null references core.tactics_projects(id) on delete cascade,
  -- One board of the project, or null for all of them.
  board_id text check (board_id is null or length(board_id) between 1 and 80),
  created_by uuid not null references core.profiles(id),
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);
create index tactics_share_links_project on core.tactics_share_links (project_id) where revoked_at is null;

alter table core.tactics_share_links enable row level security;
revoke all on core.tactics_share_links from public, anon, authenticated;

create or replace function internal.tactics_require_owner(target_project_id uuid)
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if not exists (select 1 from core.tactics_projects where id = target_project_id and owner_id = auth.uid()) then
    raise insufficient_privilege using message = 'not_found';
  end if;
end;
$$;

-- A new link, or the live one already made for the same board.
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
  where link.project_id = target_project_id and link.board_id is not distinct from target_board_id and link.revoked_at is null
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
    where link.project_id = target_project_id and link.revoked_at is null), '[]'::jsonb);
end;
$$;

create or replace function internal.revoke_tactics_share_link_for_actor(target_token text)
returns void language plpgsql security definer set search_path = '' as $$
declare link core.tactics_share_links;
begin
  select * into link from core.tactics_share_links where token = target_token;
  if link.token is null then raise insufficient_privilege using message = 'not_found'; end if;
  perform internal.tactics_require_owner(link.project_id);
  update core.tactics_share_links set revoked_at = now() where token = target_token and revoked_at is null;
end;
$$;

-- What a link shows: the project's name and kind and its boards (or the
-- one board), as last saved; null for an unknown or revoked link.
create or replace function internal.get_shared_tactics(target_token text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'name', project.name, 'kind', project.kind, 'updated_at', project.updated_at,
    'team_name', (select team.name from core.teams team where team.id = project.teamzone_team_id),
    'board_id', link.board_id,
    'boards', case when link.board_id is null then project.document->'boards'
      else coalesce((select jsonb_agg(board) from jsonb_array_elements(project.document->'boards') board
        where board->>'id' = link.board_id), '[]'::jsonb) end
  )
  from core.tactics_share_links link
  join core.tactics_projects project on project.id = link.project_id
  where link.token = target_token and link.revoked_at is null
$$;

create or replace function api.create_tactics_share_link(target_project_id uuid, target_board_id text) returns text language sql security invoker set search_path = '' as
$$ select internal.create_tactics_share_link_for_actor(target_project_id, target_board_id) $$;
create or replace function api.list_tactics_share_links(target_project_id uuid) returns jsonb language sql stable security invoker set search_path = '' as
$$ select internal.list_tactics_share_links_for_actor(target_project_id) $$;
create or replace function api.revoke_tactics_share_link(target_token text) returns void language sql security invoker set search_path = '' as
$$ select internal.revoke_tactics_share_link_for_actor(target_token) $$;
create or replace function api.get_shared_tactics(target_token text) returns jsonb language sql stable security invoker set search_path = '' as
$$ select internal.get_shared_tactics(target_token) $$;

revoke all on function
  internal.tactics_require_owner(uuid), internal.create_tactics_share_link_for_actor(uuid, text),
  internal.list_tactics_share_links_for_actor(uuid), internal.revoke_tactics_share_link_for_actor(text),
  internal.get_shared_tactics(text),
  api.create_tactics_share_link(uuid, text), api.list_tactics_share_links(uuid), api.revoke_tactics_share_link(text),
  api.get_shared_tactics(text)
from public, anon, authenticated;
grant execute on function
  internal.tactics_require_owner(uuid), internal.create_tactics_share_link_for_actor(uuid, text),
  internal.list_tactics_share_links_for_actor(uuid), internal.revoke_tactics_share_link_for_actor(text),
  api.create_tactics_share_link(uuid, text), api.list_tactics_share_links(uuid), api.revoke_tactics_share_link(text)
to authenticated;
-- The shared page is read by Webtools' server only.
grant execute on function internal.get_shared_tactics(text), api.get_shared_tactics(text) to service_role;
notify pgrst, 'reload schema';
