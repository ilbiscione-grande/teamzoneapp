-- Tacticsboard: a project's earlier versions, for its owner to go back to
-- (docs/implementation/tacticsboard-teamzone-link.md, step 1). Before a
-- save overwrites the document, the document as it was is kept as a
-- version, but not for every autosave: when no version was taken in the
-- last half hour (an editing session's start), when someone else saves
-- than saved last (once other leaders may edit), and always before a
-- restore, so a restore can be undone. A trigger takes them, so every
-- write is covered (the editor's save, a training pass written back).
-- The ten latest are always kept, older ones for 90 days.

create table core.tactics_project_versions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references core.tactics_projects(id) on delete cascade,
  revision bigint not null,
  name text not null,
  document jsonb not null,
  -- Who saved this content, and when: the project's last save before it was overwritten.
  saved_by uuid references core.profiles(id) on delete set null,
  saved_at timestamptz not null,
  reason text not null check (reason in ('edit', 'other_editor', 'before_restore')),
  created_at timestamptz not null default now()
);
create index tactics_project_versions_project on core.tactics_project_versions (project_id, created_at desc);

alter table core.tactics_project_versions enable row level security;
revoke all on core.tactics_project_versions from public, anon, authenticated;

alter table core.tactics_projects add column last_saved_by uuid references core.profiles(id) on delete set null;

-- Before an update that changes the document or the name: the old content as
-- a version when one is due, and who saves now. A restore asks for its
-- version through the transaction setting tactics.version_reason.
create or replace function internal.tactics_keep_version()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  asked text := nullif(current_setting('tactics.version_reason', true), '');
  saver uuid := coalesce(auth.uid(), new.last_saved_by);
  reason text;
begin
  if new.document is not distinct from old.document and new.name is not distinct from old.name then return new; end if;
  new.last_saved_by := saver;
  if asked = 'before_restore' then
    reason := 'before_restore';
  elsif old.last_saved_by is not null and saver is distinct from old.last_saved_by then
    reason := 'other_editor';
  elsif not exists (select 1 from core.tactics_project_versions version
    where version.project_id = old.id and version.created_at > now() - interval '30 minutes') then
    reason := 'edit';
  end if;
  if reason is null then return new; end if;
  insert into core.tactics_project_versions (project_id, revision, name, document, saved_by, saved_at, reason)
  values (old.id, old.revision, old.name, old.document, coalesce(old.last_saved_by, old.owner_id), old.updated_at, reason);
  delete from core.tactics_project_versions version
  where version.project_id = old.id and version.created_at < now() - interval '90 days'
    and version.id not in (select kept.id from core.tactics_project_versions kept
      where kept.project_id = old.id order by kept.created_at desc, kept.revision desc limit 10);
  return new;
end;
$$;

create trigger tactics_projects_keep_version before update on core.tactics_projects
  for each row execute function internal.tactics_keep_version();

-- The owner's project, locked or not; not found for anyone else.
create or replace function internal.tactics_owned_project(target_project_id uuid)
returns core.tactics_projects language plpgsql stable security definer set search_path = '' as $$
declare project core.tactics_projects;
begin
  select * into project from core.tactics_projects where id = target_project_id;
  if project.id is null or project.owner_id is distinct from auth.uid() then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return project;
end;
$$;

-- The versions, the latest first, without their documents: what each held in short.
create or replace function internal.list_tactics_versions_for_actor(target_project_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform internal.tactics_owned_project(target_project_id);
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
  perform internal.tactics_owned_project(version.project_id);
  return jsonb_build_object('id', version.id, 'name', version.name, 'saved_at', version.saved_at, 'document', version.document);
end;
$$;

-- The version's name and boards back in the project, the project as it was
-- kept first; refused, as a save is, when the project changed since it was read.
create or replace function internal.restore_tactics_version_for_actor(target_version_id uuid, expected_revision bigint)
returns bigint language plpgsql security definer set search_path = '' as $$
declare version core.tactics_project_versions; project core.tactics_projects;
begin
  select * into version from core.tactics_project_versions where id = target_version_id;
  if version.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  perform internal.tactics_owned_project(version.project_id);
  select * into project from core.tactics_projects where id = version.project_id for update;
  if project.revision <> expected_revision then raise serialization_failure using message = 'stale_revision'; end if;
  perform set_config('tactics.version_reason', 'before_restore', true);
  update core.tactics_projects set name = version.name, document = version.document, revision = revision + 1, updated_at = now()
  where id = project.id;
  perform set_config('tactics.version_reason', '', true);
  return project.revision + 1;
end;
$$;

create or replace function api.list_tactics_versions(target_project_id uuid) returns jsonb language sql stable security invoker set search_path = '' as
$$ select internal.list_tactics_versions_for_actor(target_project_id) $$;
create or replace function api.get_tactics_version(target_version_id uuid) returns jsonb language sql stable security invoker set search_path = '' as
$$ select internal.get_tactics_version_for_actor(target_version_id) $$;
create or replace function api.restore_tactics_version(target_version_id uuid, expected_revision bigint) returns bigint language sql security invoker set search_path = '' as
$$ select internal.restore_tactics_version_for_actor(target_version_id, expected_revision) $$;

revoke all on function
  internal.tactics_keep_version(), internal.tactics_owned_project(uuid),
  internal.list_tactics_versions_for_actor(uuid), internal.get_tactics_version_for_actor(uuid),
  internal.restore_tactics_version_for_actor(uuid, bigint),
  api.list_tactics_versions(uuid), api.get_tactics_version(uuid), api.restore_tactics_version(uuid, bigint)
from public, anon, authenticated;
grant execute on function
  internal.tactics_owned_project(uuid),
  internal.list_tactics_versions_for_actor(uuid), internal.get_tactics_version_for_actor(uuid),
  internal.restore_tactics_version_for_actor(uuid, bigint),
  api.list_tactics_versions(uuid), api.get_tactics_version(uuid), api.restore_tactics_version(uuid, bigint)
to authenticated;
