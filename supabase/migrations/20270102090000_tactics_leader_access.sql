-- Tacticsboard: the other leaders of a project's team may watch it, or edit
-- it when its owner lets them (docs/implementation/tacticsboard-teamzone-link.md,
-- step 2). A team's leaders are those who lead it in TeamZone
-- (internal.tournament_actor_teams). They save the boards only; the name,
-- kind and team, sharing, folders, live lessons, the library, the owner's
-- own notes, restoring a version and removing stay the owner's. Two saving
-- at once are kept apart by the revision as before, and the versions
-- (20270101090000) keep what one wrote before another saves over it.

alter table core.tactics_projects
  add column leader_access text not null default 'view' check (leader_access in ('view', 'edit'));

-- The signed-in person's access to a project: 'owner', 'edit', 'view' or null.
create or replace function internal.tactics_project_access(project core.tactics_projects)
returns text language sql stable security definer set search_path = '' as $$
  select case
    when auth.uid() is null or project.id is null then null
    when project.owner_id = auth.uid() then 'owner'
    when project.teamzone_team_id is not null
      and exists (select 1 from internal.tournament_actor_teams() team where team.team_id = project.teamzone_team_id)
      then project.leader_access
  end
$$;

-- A project as its readers see it: the owner's notes for the owner alone.
create or replace function internal.get_tactics_project_for_actor(target_project_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare project core.tactics_projects; access text;
begin
  select * into project from core.tactics_projects where id = target_project_id;
  access := internal.tactics_project_access(project);
  if access is null then raise insufficient_privilege using message = 'not_found'; end if;
  return internal.tactics_project_summary(project) || jsonb_build_object(
    'document', project.document,
    'host_notes', case when access = 'owner' then project.host_notes else '{}'::jsonb end,
    'access', access, 'leader_access', project.leader_access,
    'owner_name', (select profile.display_name from core.profiles profile where profile.id = project.owner_id));
end;
$$;

-- The owner saves all of it; a leader who may edit, the document alone.
-- A stale revision is refused, not merged.
create or replace function internal.save_tactics_project_for_actor(
  target_project_id uuid, expected_revision bigint, project_name text, project_kind text,
  target_team_id uuid, project_document jsonb
) returns bigint language plpgsql security definer set search_path = '' as $$
declare project core.tactics_projects; access text;
begin
  select * into project from core.tactics_projects where id = target_project_id for update;
  access := internal.tactics_project_access(project);
  if access is null or access = 'view' then raise insufficient_privilege using message = 'not_found'; end if;
  if project.revision <> expected_revision then raise serialization_failure using message = 'stale_revision'; end if;
  if jsonb_typeof(coalesce(project_document, 'null')) <> 'object' then raise invalid_parameter_value using message = 'invalid_document'; end if;
  if access = 'edit' then
    update core.tactics_projects set document = project_document, revision = revision + 1, updated_at = now()
    where id = project.id;
    return project.revision + 1;
  end if;
  if project_kind not in ('match', 'training', 'education') then raise invalid_parameter_value using message = 'invalid_kind'; end if;
  if target_team_id is distinct from project.teamzone_team_id then perform internal.tactics_require_team(target_team_id); end if;
  update core.tactics_projects set name = btrim(project_name), kind = project_kind, teamzone_team_id = target_team_id,
    document = project_document, revision = revision + 1, updated_at = now()
  where id = project.id;
  return project.revision + 1;
end;
$$;

-- Other leaders' projects for the teams you lead, the latest first.
create or replace function internal.list_team_tactics_projects_for_actor()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(internal.tactics_project_summary(project) || jsonb_build_object(
      'access', project.leader_access,
      'owner_name', (select profile.display_name from core.profiles profile where profile.id = project.owner_id))
    order by project.updated_at desc), '[]'::jsonb)
  from core.tactics_projects project
  where project.owner_id is distinct from auth.uid()
    and project.teamzone_team_id in (select team.team_id from internal.tournament_actor_teams() team)
$$;

-- What the team's other leaders may do; the owner's to set.
create or replace function internal.set_tactics_leader_access_for_actor(target_project_id uuid, access text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if access is null or access not in ('view', 'edit') then raise invalid_parameter_value using message = 'invalid_access'; end if;
  update core.tactics_projects set leader_access = access where id = target_project_id and owner_id = auth.uid();
  if not found then raise insufficient_privilege using message = 'not_found'; end if;
end;
$$;

-- The versions are seen by those who may edit; put back by the owner alone.
create or replace function internal.tactics_versions_project(target_project_id uuid)
returns core.tactics_projects language plpgsql stable security definer set search_path = '' as $$
declare project core.tactics_projects;
begin
  select * into project from core.tactics_projects where id = target_project_id;
  if coalesce(internal.tactics_project_access(project), 'view') = 'view' then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return project;
end;
$$;

create or replace function internal.list_tactics_versions_for_actor(target_project_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform internal.tactics_versions_project(target_project_id);
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', version.id, 'revision', version.revision, 'name', version.name,
      'saved_at', version.saved_at, 'reason', version.reason,
      'saved_by_me', version.saved_by = auth.uid(),
      'saved_by_name', (select profile.display_name from core.profiles profile where profile.id = version.saved_by),
      'boards', coalesce((select jsonb_agg(coalesce(board->>'name', '')) from jsonb_array_elements(
        case when jsonb_typeof(version.document->'boards') = 'array' then version.document->'boards' else '[]'::jsonb end) board), '[]'::jsonb)
    ) order by version.created_at desc, version.revision desc)
    from core.tactics_project_versions version where version.project_id = target_project_id), '[]'::jsonb);
end;
$$;

create or replace function internal.get_tactics_version_for_actor(target_version_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare version core.tactics_project_versions;
begin
  select * into version from core.tactics_project_versions where id = target_version_id;
  if version.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  perform internal.tactics_versions_project(version.project_id);
  return jsonb_build_object('id', version.id, 'name', version.name, 'saved_at', version.saved_at, 'document', version.document);
end;
$$;

create or replace function api.list_team_tactics_projects() returns jsonb language sql stable security invoker set search_path = '' as
$$ select internal.list_team_tactics_projects_for_actor() $$;
create or replace function api.set_tactics_leader_access(target_project_id uuid, access text) returns void language sql security invoker set search_path = '' as
$$ select internal.set_tactics_leader_access_for_actor(target_project_id, access) $$;

revoke all on function
  internal.tactics_project_access(core.tactics_projects), internal.list_team_tactics_projects_for_actor(),
  internal.set_tactics_leader_access_for_actor(uuid, text), internal.tactics_versions_project(uuid),
  api.list_team_tactics_projects(), api.set_tactics_leader_access(uuid, text)
from public, anon, authenticated;
grant execute on function
  internal.tactics_project_access(core.tactics_projects), internal.list_team_tactics_projects_for_actor(),
  internal.set_tactics_leader_access_for_actor(uuid, text), internal.tactics_versions_project(uuid),
  api.list_team_tactics_projects(), api.set_tactics_leader_access(uuid, text)
to authenticated;
