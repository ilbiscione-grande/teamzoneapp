-- Tacticsboard's folders (the product owner, 2026-10-29): projects that
-- belong together, such as the parts of a game idea ("Spelidé 2026" with
-- Speluppbyggnad, Komma till avslut and Omställning offensivt). A project is
-- linked into a folder, not moved or copied: the same project may be in
-- several folders (Speluppbyggnad in both Spelidé 2026 and 2027), and a
-- change to it shows in all of them. A folder keeps its projects in the
-- order the owner sets. Taking a project out of a folder, or removing the
-- folder, only removes the links; removing a project takes it out of every
-- folder. Folders are private to their owner, as the projects are; sharing
-- a folder may come later, as a share link.

create table core.tactics_folders (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references core.profiles(id),
  name text not null check (length(btrim(name)) between 1 and 120),
  description text not null default '' check (length(description) <= 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index tactics_folders_owner on core.tactics_folders (owner_id, updated_at desc);

create table core.tactics_folder_projects (
  folder_id uuid not null references core.tactics_folders(id) on delete cascade,
  project_id uuid not null references core.tactics_projects(id) on delete cascade,
  position integer not null check (position >= 0),
  added_at timestamptz not null default now(),
  primary key (folder_id, project_id)
);
create index tactics_folder_projects_project on core.tactics_folder_projects (project_id);

alter table core.tactics_folders enable row level security;
alter table core.tactics_folder_projects enable row level security;
revoke all on core.tactics_folders, core.tactics_folder_projects from public, anon, authenticated;

-- A folder for the lists: its name, description and how many projects.
create or replace function internal.tactics_folder_summary(folder core.tactics_folders)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', folder.id, 'name', folder.name, 'description', folder.description,
    'project_count', (select count(*) from core.tactics_folder_projects link where link.folder_id = folder.id),
    'created_at', folder.created_at, 'updated_at', folder.updated_at
  )
$$;

create or replace function internal.tactics_require_folder_owner(target_folder_id uuid)
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  if not exists (select 1 from core.tactics_folders where id = target_folder_id and owner_id = auth.uid()) then
    raise insufficient_privilege using message = 'not_found';
  end if;
end;
$$;

-- Links a project at the end of a folder; already there, it stays where it
-- is. At most 100 projects in a folder.
create or replace function internal.tactics_link_folder_project(target_folder_id uuid, target_project_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from core.tactics_folder_projects
    where folder_id = target_folder_id and project_id = target_project_id) then return; end if;
  if (select count(*) from core.tactics_folder_projects where folder_id = target_folder_id) >= 100 then
    raise check_violation using message = 'too_many_projects';
  end if;
  insert into core.tactics_folder_projects (folder_id, project_id, position)
  values (target_folder_id, target_project_id, coalesce((
    select max(position) + 1 from core.tactics_folder_projects where folder_id = target_folder_id), 0));
  update core.tactics_folders set updated_at = now() where id = target_folder_id;
end;
$$;

-- Your folders, the latest changed first.
create or replace function internal.list_my_tactics_folders_for_actor()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  return coalesce((select jsonb_agg(internal.tactics_folder_summary(folder) order by folder.updated_at desc)
    from core.tactics_folders folder where folder.owner_id = auth.uid()), '[]'::jsonb);
end;
$$;

-- A new folder. At most 200.
create or replace function internal.create_tactics_folder_for_actor(folder_name text, folder_description text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare created core.tactics_folders;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  if (select count(*) from core.tactics_folders where owner_id = auth.uid()) >= 200 then
    raise check_violation using message = 'too_many_folders';
  end if;
  insert into core.tactics_folders (owner_id, name, description)
  values (auth.uid(), btrim(coalesce(folder_name, '')), btrim(coalesce(folder_description, '')))
  returning * into created;
  return internal.tactics_folder_summary(created);
end;
$$;

-- A folder with its projects in order.
create or replace function internal.get_tactics_folder_for_actor(target_folder_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform internal.tactics_require_folder_owner(target_folder_id);
  return (select internal.tactics_folder_summary(folder) || jsonb_build_object('projects', coalesce((
      select jsonb_agg(internal.tactics_project_summary(project) order by link.position, link.added_at)
      from core.tactics_folder_projects link
      join core.tactics_projects project on project.id = link.project_id
      where link.folder_id = folder.id), '[]'::jsonb))
    from core.tactics_folders folder where folder.id = target_folder_id);
end;
$$;

create or replace function internal.update_tactics_folder_for_actor(target_folder_id uuid, folder_name text, folder_description text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform internal.tactics_require_folder_owner(target_folder_id);
  update core.tactics_folders
  set name = btrim(coalesce(folder_name, '')), description = btrim(coalesce(folder_description, '')), updated_at = now()
  where id = target_folder_id;
end;
$$;

-- The folder goes; its projects stay.
create or replace function internal.delete_tactics_folder_for_actor(target_folder_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  delete from core.tactics_folders where id = target_folder_id and owner_id = auth.uid();
  if not found then raise insufficient_privilege using message = 'not_found'; end if;
end;
$$;

create or replace function internal.add_tactics_folder_project_for_actor(target_folder_id uuid, target_project_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform internal.tactics_require_folder_owner(target_folder_id);
  perform internal.tactics_require_owner(target_project_id);
  perform internal.tactics_link_folder_project(target_folder_id, target_project_id);
end;
$$;

-- Takes a project out of a folder; the project stays.
create or replace function internal.remove_tactics_folder_project_for_actor(target_folder_id uuid, target_project_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform internal.tactics_require_folder_owner(target_folder_id);
  delete from core.tactics_folder_projects where folder_id = target_folder_id and project_id = target_project_id;
  if found then update core.tactics_folders set updated_at = now() where id = target_folder_id; end if;
end;
$$;

-- The folder's projects in a new order: the same projects, each once.
create or replace function internal.order_tactics_folder_for_actor(target_folder_id uuid, project_ids uuid[])
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform internal.tactics_require_folder_owner(target_folder_id);
  if project_ids is null
    or cardinality(project_ids) <> (select count(distinct listed.id) from unnest(project_ids) listed(id))
    or cardinality(project_ids) <> (select count(*) from core.tactics_folder_projects where folder_id = target_folder_id)
    or exists (select 1 from unnest(project_ids) listed(id) where not exists (select 1 from core.tactics_folder_projects link
      where link.folder_id = target_folder_id and link.project_id = listed.id)) then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  update core.tactics_folder_projects link set position = ordered.ordinality - 1
  from unnest(project_ids) with ordinality ordered(id, ordinality)
  where link.folder_id = target_folder_id and link.project_id = ordered.id;
  update core.tactics_folders set updated_at = now() where id = target_folder_id;
end;
$$;

-- The folders a project is in, all at once: links it at the end of those
-- it is new in, takes it out of the others.
create or replace function internal.set_tactics_project_folders_for_actor(target_project_id uuid, folder_ids uuid[])
returns void language plpgsql security definer set search_path = '' as $$
declare wanted uuid[] := coalesce(folder_ids, '{}'::uuid[]); wanted_folder uuid;
begin
  perform internal.tactics_require_owner(target_project_id);
  if exists (select 1 from unnest(wanted) listed(id) where not exists (select 1 from core.tactics_folders folder
    where folder.id = listed.id and folder.owner_id = auth.uid())) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  update core.tactics_folders folder set updated_at = now()
  where folder.id in (select link.folder_id from core.tactics_folder_projects link
    where link.project_id = target_project_id and not link.folder_id = any(wanted));
  delete from core.tactics_folder_projects link
  where link.project_id = target_project_id and not link.folder_id = any(wanted);
  foreach wanted_folder in array wanted loop
    perform internal.tactics_link_folder_project(wanted_folder, target_project_id);
  end loop;
end;
$$;

-- As in 20261216090000, with the folders each project is in.
create or replace function internal.search_my_tactics_projects_for_actor(
  search_text text, project_kind text, exercise_part text, game_phase text, age_class text, game_form text
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare words text[];
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  if length(coalesce(search_text, '')) > 100 then raise invalid_parameter_value using message = 'invalid_input'; end if;
  words := array_remove(regexp_split_to_array(lower(btrim(coalesce(search_text, ''))), '\s+'), '');
  return coalesce((
    select jsonb_agg(internal.tactics_project_summary(project) || jsonb_build_object(
      'published', coalesce((
        select jsonb_agg(jsonb_build_object(
          'item_id', item.id, 'kind', item.kind, 'title', item.title, 'board_id', item.source_board_id,
          'shared_id', shared.id, 'version', shared.version, 'hidden', shared.hidden,
          'current', shared.updated_at >= item.updated_at, 'club_id', shared.club_id,
          'club_name', (select club.name from core.clubs club where club.id = shared.club_id)
        ) order by item.kind, item.title)
        from core.tactics_library_items item
        join core.tactics_shared_items shared on shared.library_item_id = item.id
        where item.source_project_id = project.id and item.owner_id = auth.uid()), '[]'::jsonb),
      'folders', coalesce((
        select jsonb_agg(jsonb_build_object('id', folder.id, 'name', folder.name) order by folder.name)
        from core.tactics_folder_projects link
        join core.tactics_folders folder on folder.id = link.folder_id
        where link.project_id = project.id), '[]'::jsonb)
    ) order by project.updated_at desc)
    from core.tactics_projects project
    where project.owner_id = auth.uid()
      and internal.tactics_project_matches(project, words, project_kind, exercise_part, game_phase, age_class, game_form)
  ), '[]'::jsonb);
end;
$$;

create or replace function api.list_my_tactics_folders() returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.list_my_tactics_folders_for_actor() $$;
create or replace function api.create_tactics_folder(folder_name text, folder_description text) returns jsonb
language sql security invoker set search_path = '' as $$ select internal.create_tactics_folder_for_actor(folder_name, folder_description) $$;
create or replace function api.get_tactics_folder(target_folder_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.get_tactics_folder_for_actor(target_folder_id) $$;
create or replace function api.update_tactics_folder(target_folder_id uuid, folder_name text, folder_description text) returns void
language sql security invoker set search_path = '' as $$
  select internal.update_tactics_folder_for_actor(target_folder_id, folder_name, folder_description) $$;
create or replace function api.delete_tactics_folder(target_folder_id uuid) returns void
language sql security invoker set search_path = '' as $$ select internal.delete_tactics_folder_for_actor(target_folder_id) $$;
create or replace function api.add_tactics_folder_project(target_folder_id uuid, target_project_id uuid) returns void
language sql security invoker set search_path = '' as $$
  select internal.add_tactics_folder_project_for_actor(target_folder_id, target_project_id) $$;
create or replace function api.remove_tactics_folder_project(target_folder_id uuid, target_project_id uuid) returns void
language sql security invoker set search_path = '' as $$
  select internal.remove_tactics_folder_project_for_actor(target_folder_id, target_project_id) $$;
create or replace function api.order_tactics_folder(target_folder_id uuid, project_ids uuid[]) returns void
language sql security invoker set search_path = '' as $$ select internal.order_tactics_folder_for_actor(target_folder_id, project_ids) $$;
create or replace function api.set_tactics_project_folders(target_project_id uuid, folder_ids uuid[]) returns void
language sql security invoker set search_path = '' as $$
  select internal.set_tactics_project_folders_for_actor(target_project_id, folder_ids) $$;

revoke all on function
  internal.tactics_folder_summary(core.tactics_folders), internal.tactics_require_folder_owner(uuid),
  internal.tactics_link_folder_project(uuid, uuid), internal.list_my_tactics_folders_for_actor(),
  internal.create_tactics_folder_for_actor(text, text), internal.get_tactics_folder_for_actor(uuid),
  internal.update_tactics_folder_for_actor(uuid, text, text), internal.delete_tactics_folder_for_actor(uuid),
  internal.add_tactics_folder_project_for_actor(uuid, uuid), internal.remove_tactics_folder_project_for_actor(uuid, uuid),
  internal.order_tactics_folder_for_actor(uuid, uuid[]), internal.set_tactics_project_folders_for_actor(uuid, uuid[]),
  api.list_my_tactics_folders(), api.create_tactics_folder(text, text), api.get_tactics_folder(uuid),
  api.update_tactics_folder(uuid, text, text), api.delete_tactics_folder(uuid),
  api.add_tactics_folder_project(uuid, uuid), api.remove_tactics_folder_project(uuid, uuid),
  api.order_tactics_folder(uuid, uuid[]), api.set_tactics_project_folders(uuid, uuid[])
from public, anon, authenticated;
grant execute on function
  internal.list_my_tactics_folders_for_actor(), internal.create_tactics_folder_for_actor(text, text),
  internal.get_tactics_folder_for_actor(uuid), internal.update_tactics_folder_for_actor(uuid, text, text),
  internal.delete_tactics_folder_for_actor(uuid), internal.add_tactics_folder_project_for_actor(uuid, uuid),
  internal.remove_tactics_folder_project_for_actor(uuid, uuid), internal.order_tactics_folder_for_actor(uuid, uuid[]),
  internal.set_tactics_project_folders_for_actor(uuid, uuid[]),
  api.list_my_tactics_folders(), api.create_tactics_folder(text, text), api.get_tactics_folder(uuid),
  api.update_tactics_folder(uuid, text, text), api.delete_tactics_folder(uuid),
  api.add_tactics_folder_project(uuid, uuid), api.remove_tactics_folder_project(uuid, uuid),
  api.order_tactics_folder(uuid, uuid[]), api.set_tactics_project_folders(uuid, uuid[])
to authenticated;
notify pgrst, 'reload schema';
