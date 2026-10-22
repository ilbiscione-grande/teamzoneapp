-- Webtools Tacticsboard, part 1: projects of tactics boards saved on the
-- TeamZone account. A project's boards and frames are one document (jsonb,
-- with its own schema version) written whole with a revision check, so two
-- tabs cannot overwrite each other unseen. A project may name the TeamZone
-- team it is for; boards have stable ids, so an activity can later link one
-- (a match review in the preparation, a training's exercises).

create table core.tactics_projects (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references core.profiles(id),
  name text not null check (length(btrim(name)) between 1 and 120),
  kind text not null default 'match' check (kind in ('match', 'training', 'education')),
  teamzone_team_id uuid references core.teams(id),
  document jsonb not null,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (jsonb_typeof(document) = 'object'),
  -- A project stays well under PostgREST's request limit.
  check (pg_column_size(document) <= 4000000)
);
create index tactics_projects_owner on core.tactics_projects (owner_id, updated_at desc);

alter table core.tactics_projects enable row level security;
revoke all on core.tactics_projects from public, anon, authenticated;

create or replace function internal.tactics_project_summary(project core.tactics_projects)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', project.id, 'name', project.name, 'kind', project.kind,
    'teamzone_team_id', project.teamzone_team_id,
    'team_name', (select team.name from core.teams team where team.id = project.teamzone_team_id),
    'board_count', coalesce(jsonb_array_length(project.document->'boards'), 0),
    'revision', project.revision, 'created_at', project.created_at, 'updated_at', project.updated_at
  )
$$;

-- Your projects, the latest first.
create or replace function internal.list_my_tactics_projects_for_actor()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(internal.tactics_project_summary(project) order by project.updated_at desc), '[]'::jsonb)
  from core.tactics_projects project where project.owner_id = auth.uid()
$$;

-- The team must be one you lead, as for tournament registrations.
create or replace function internal.tactics_require_team(target_team_id uuid)
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if target_team_id is not null and not exists (select 1 from internal.tournament_actor_teams() t where t.team_id = target_team_id) then
    raise insufficient_privilege using message = 'not_team_leader';
  end if;
end;
$$;

create or replace function internal.create_tactics_project_for_actor(
  project_name text, project_kind text, target_team_id uuid, project_document jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare created core.tactics_projects;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  if project_kind not in ('match', 'training', 'education') then raise invalid_parameter_value using message = 'invalid_kind'; end if;
  if jsonb_typeof(coalesce(project_document, 'null')) <> 'object' then raise invalid_parameter_value using message = 'invalid_document'; end if;
  perform internal.tactics_require_team(target_team_id);
  insert into core.tactics_projects (owner_id, name, kind, teamzone_team_id, document)
  values (auth.uid(), btrim(project_name), project_kind, target_team_id, project_document)
  returning * into created;
  return internal.tactics_project_summary(created);
end;
$$;

create or replace function internal.get_tactics_project_for_actor(target_project_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare project core.tactics_projects;
begin
  select * into project from core.tactics_projects where id = target_project_id;
  if project.id is null or project.owner_id is distinct from auth.uid() then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return internal.tactics_project_summary(project) || jsonb_build_object('document', project.document);
end;
$$;

-- Writes the whole document when the revision is the one you read; the
-- new revision back. A stale revision is refused, not merged.
create or replace function internal.save_tactics_project_for_actor(
  target_project_id uuid, expected_revision bigint, project_name text, project_kind text,
  target_team_id uuid, project_document jsonb
) returns bigint language plpgsql security definer set search_path = '' as $$
declare project core.tactics_projects;
begin
  select * into project from core.tactics_projects where id = target_project_id for update;
  if project.id is null or project.owner_id is distinct from auth.uid() then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if project.revision <> expected_revision then raise serialization_failure using message = 'stale_revision'; end if;
  if project_kind not in ('match', 'training', 'education') then raise invalid_parameter_value using message = 'invalid_kind'; end if;
  if jsonb_typeof(coalesce(project_document, 'null')) <> 'object' then raise invalid_parameter_value using message = 'invalid_document'; end if;
  if target_team_id is distinct from project.teamzone_team_id then perform internal.tactics_require_team(target_team_id); end if;
  update core.tactics_projects set name = btrim(project_name), kind = project_kind, teamzone_team_id = target_team_id,
    document = project_document, revision = revision + 1, updated_at = now()
  where id = project.id;
  return project.revision + 1;
end;
$$;

create or replace function internal.delete_tactics_project_for_actor(target_project_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from core.tactics_projects where id = target_project_id and owner_id = auth.uid();
  if not found then raise insufficient_privilege using message = 'not_found'; end if;
end;
$$;

-- The squad of one of your teams for the board: active players with their
-- shirt number (20261123080000) and main position.
create or replace function internal.list_tactics_team_players_for_actor(target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if target_team_id is null then raise invalid_parameter_value using message = 'not_found'; end if;
  perform internal.tactics_require_team(target_team_id);
  return coalesce((select jsonb_agg(player order by (player->>'number')::integer nulls last, player->>'name') from (
    select distinct on (person.id) jsonb_build_object(
      'person_id', person.id, 'name', person.display_name, 'number', details.jersey_number,
      'position', coalesce(nullif(btrim(details.main_position), ''), details.positions[1])
    ) player
    from core.assignments assignment
    join core.club_people person on person.id = assignment.club_person_id
    left join core.team_person_details details on details.team_id = assignment.team_id
      and details.club_person_id = person.id
    where assignment.team_id = target_team_id and assignment.role_package = 'player' and assignment.state = 'active'
      and assignment.starts_at <= now() and (assignment.ends_at is null or assignment.ends_at > now())
    order by person.id
  ) players), '[]'::jsonb);
end;
$$;

create or replace function api.list_my_tactics_projects() returns jsonb language sql stable security invoker set search_path = '' as
$$ select internal.list_my_tactics_projects_for_actor() $$;
create or replace function api.create_tactics_project(project_name text, project_kind text, target_team_id uuid, project_document jsonb)
returns jsonb language sql security invoker set search_path = '' as
$$ select internal.create_tactics_project_for_actor(project_name, project_kind, target_team_id, project_document) $$;
create or replace function api.get_tactics_project(target_project_id uuid) returns jsonb language sql stable security invoker set search_path = '' as
$$ select internal.get_tactics_project_for_actor(target_project_id) $$;
create or replace function api.save_tactics_project(target_project_id uuid, expected_revision bigint, project_name text, project_kind text, target_team_id uuid, project_document jsonb)
returns bigint language sql security invoker set search_path = '' as
$$ select internal.save_tactics_project_for_actor(target_project_id, expected_revision, project_name, project_kind, target_team_id, project_document) $$;
create or replace function api.delete_tactics_project(target_project_id uuid) returns void language sql security invoker set search_path = '' as
$$ select internal.delete_tactics_project_for_actor(target_project_id) $$;
create or replace function api.list_tactics_team_players(target_team_id uuid) returns jsonb language sql stable security invoker set search_path = '' as
$$ select internal.list_tactics_team_players_for_actor(target_team_id) $$;

revoke all on function
  internal.tactics_project_summary(core.tactics_projects), internal.list_my_tactics_projects_for_actor(),
  internal.tactics_require_team(uuid), internal.create_tactics_project_for_actor(text, text, uuid, jsonb),
  internal.get_tactics_project_for_actor(uuid), internal.save_tactics_project_for_actor(uuid, bigint, text, text, uuid, jsonb),
  internal.delete_tactics_project_for_actor(uuid), internal.list_tactics_team_players_for_actor(uuid),
  api.list_my_tactics_projects(), api.create_tactics_project(text, text, uuid, jsonb), api.get_tactics_project(uuid),
  api.save_tactics_project(uuid, bigint, text, text, uuid, jsonb), api.delete_tactics_project(uuid),
  api.list_tactics_team_players(uuid)
from public, anon, authenticated;
grant execute on function
  internal.tactics_project_summary(core.tactics_projects), internal.list_my_tactics_projects_for_actor(),
  internal.tactics_require_team(uuid), internal.create_tactics_project_for_actor(text, text, uuid, jsonb),
  internal.get_tactics_project_for_actor(uuid), internal.save_tactics_project_for_actor(uuid, bigint, text, text, uuid, jsonb),
  internal.delete_tactics_project_for_actor(uuid), internal.list_tactics_team_players_for_actor(uuid),
  api.list_my_tactics_projects(), api.create_tactics_project(text, text, uuid, jsonb), api.get_tactics_project(uuid),
  api.save_tactics_project(uuid, bigint, text, text, uuid, jsonb), api.delete_tactics_project(uuid),
  api.list_tactics_team_players(uuid)
to authenticated;
