-- Tacticsboard: a shared link shows the project's club logo on the pitch,
-- as the editor does. Both shared reads now carry the document's branding
-- (null where the project has none); otherwise they are as before.

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
$$;

create or replace function internal.get_shared_tactics_folder_project(target_token text, target_project_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'name', project.name, 'kind', project.kind, 'updated_at', project.updated_at,
    'team_name', (select team.name from core.teams team where team.id = project.teamzone_team_id),
    'board_id', null, 'boards', project.document->'boards',
    'folder_name', folder.name,
    'branding', project.document->'branding'
  )
  from core.tactics_folder_share_links link
  join core.tactics_folders folder on folder.id = link.folder_id
  join core.tactics_folder_projects member on member.folder_id = folder.id and member.project_id = target_project_id
  join core.tactics_projects project on project.id = member.project_id
  where link.token = target_token and link.revoked_at is null
$$;
