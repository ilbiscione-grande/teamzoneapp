-- Tacticsboard's folders shared by a link (the product owner, 2026-10-29),
-- as a project is (20261124090000): anyone with the link sees the folder's
-- name, description and projects in their order, and watches and plays each
-- project's boards without an account, always as last saved. The link
-- follows the folder: a project linked in later shows, one taken out stops
-- showing. It stops when revoked or when the folder is removed. The pages
-- are read by Webtools' server only.

create table core.tactics_folder_share_links (
  token text primary key check (token ~ '^[0-9a-f]{40}$'),
  folder_id uuid not null references core.tactics_folders(id) on delete cascade,
  created_by uuid not null references core.profiles(id),
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);
create index tactics_folder_share_links_folder on core.tactics_folder_share_links (folder_id) where revoked_at is null;

alter table core.tactics_folder_share_links enable row level security;
revoke all on core.tactics_folder_share_links from public, anon, authenticated;

-- The live link of a folder, or a new one.
create or replace function internal.create_tactics_folder_share_link_for_actor(target_folder_id uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare existing text; token text;
begin
  perform internal.tactics_require_folder_owner(target_folder_id);
  select link.token into existing from core.tactics_folder_share_links link
  where link.folder_id = target_folder_id and link.revoked_at is null limit 1;
  if existing is not null then return existing; end if;
  token := substr(replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''), 1, 40);
  insert into core.tactics_folder_share_links (token, folder_id, created_by) values (token, target_folder_id, auth.uid());
  return token;
end;
$$;

-- The folder's live link, or null.
create or replace function internal.get_tactics_folder_share_link_for_actor(target_folder_id uuid)
returns text language plpgsql stable security definer set search_path = '' as $$
begin
  perform internal.tactics_require_folder_owner(target_folder_id);
  return (select link.token from core.tactics_folder_share_links link
    where link.folder_id = target_folder_id and link.revoked_at is null order by link.created_at limit 1);
end;
$$;

create or replace function internal.revoke_tactics_folder_share_link_for_actor(target_token text)
returns void language plpgsql security definer set search_path = '' as $$
declare link core.tactics_folder_share_links;
begin
  select * into link from core.tactics_folder_share_links where token = target_token;
  if link.token is null then raise insufficient_privilege using message = 'not_found'; end if;
  perform internal.tactics_require_folder_owner(link.folder_id);
  update core.tactics_folder_share_links set revoked_at = now() where token = target_token and revoked_at is null;
end;
$$;

-- What a folder link shows: the folder and its projects in order, without
-- their boards; null for an unknown or revoked link.
create or replace function internal.get_shared_tactics_folder(target_token text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'name', folder.name, 'description', folder.description, 'updated_at', folder.updated_at,
    'projects', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', project.id, 'name', project.name, 'kind', project.kind,
        'board_count', coalesce(jsonb_array_length(project.document->'boards'), 0), 'updated_at', project.updated_at
      ) order by member.position, member.added_at)
      from core.tactics_folder_projects member
      join core.tactics_projects project on project.id = member.project_id
      where member.folder_id = folder.id), '[]'::jsonb)
  )
  from core.tactics_folder_share_links link
  join core.tactics_folders folder on folder.id = link.folder_id
  where link.token = target_token and link.revoked_at is null
$$;

-- One project of a shared folder, as a project's own link shows it
-- (internal.get_shared_tactics); null unless the project is in the folder.
create or replace function internal.get_shared_tactics_folder_project(target_token text, target_project_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'name', project.name, 'kind', project.kind, 'updated_at', project.updated_at,
    'team_name', (select team.name from core.teams team where team.id = project.teamzone_team_id),
    'board_id', null, 'boards', project.document->'boards',
    'folder_name', folder.name
  )
  from core.tactics_folder_share_links link
  join core.tactics_folders folder on folder.id = link.folder_id
  join core.tactics_folder_projects member on member.folder_id = folder.id and member.project_id = target_project_id
  join core.tactics_projects project on project.id = member.project_id
  where link.token = target_token and link.revoked_at is null
$$;

create or replace function api.create_tactics_folder_share_link(target_folder_id uuid) returns text
language sql security invoker set search_path = '' as $$ select internal.create_tactics_folder_share_link_for_actor(target_folder_id) $$;
create or replace function api.get_tactics_folder_share_link(target_folder_id uuid) returns text
language sql stable security invoker set search_path = '' as $$ select internal.get_tactics_folder_share_link_for_actor(target_folder_id) $$;
create or replace function api.revoke_tactics_folder_share_link(target_token text) returns void
language sql security invoker set search_path = '' as $$ select internal.revoke_tactics_folder_share_link_for_actor(target_token) $$;
create or replace function api.get_shared_tactics_folder(target_token text) returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.get_shared_tactics_folder(target_token) $$;
create or replace function api.get_shared_tactics_folder_project(target_token text, target_project_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$
  select internal.get_shared_tactics_folder_project(target_token, target_project_id) $$;

revoke all on function
  internal.create_tactics_folder_share_link_for_actor(uuid), internal.get_tactics_folder_share_link_for_actor(uuid),
  internal.revoke_tactics_folder_share_link_for_actor(text), internal.get_shared_tactics_folder(text),
  internal.get_shared_tactics_folder_project(text, uuid),
  api.create_tactics_folder_share_link(uuid), api.get_tactics_folder_share_link(uuid), api.revoke_tactics_folder_share_link(text),
  api.get_shared_tactics_folder(text), api.get_shared_tactics_folder_project(text, uuid)
from public, anon, authenticated;
grant execute on function
  internal.create_tactics_folder_share_link_for_actor(uuid), internal.get_tactics_folder_share_link_for_actor(uuid),
  internal.revoke_tactics_folder_share_link_for_actor(text),
  api.create_tactics_folder_share_link(uuid), api.get_tactics_folder_share_link(uuid), api.revoke_tactics_folder_share_link(text)
to authenticated;
-- The shared pages are read by Webtools' server only.
grant execute on function
  internal.get_shared_tactics_folder(text), internal.get_shared_tactics_folder_project(text, uuid),
  api.get_shared_tactics_folder(text), api.get_shared_tactics_folder_project(text, uuid)
to service_role;
notify pgrst, 'reload schema';
