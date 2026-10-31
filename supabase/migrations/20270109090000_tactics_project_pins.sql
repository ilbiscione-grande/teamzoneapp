-- Tacticsboard's start page as a grid (the product owner, 2026-10-31):
-- each project shows a small picture of its first board, and the ones you
-- pin come first.
--
-- A project's summary carries the preview of its first board (the board's
-- view, teams and first frame's objects, 20270107090000) and whether you
-- pinned it. Pins are your own: you pin your projects and the team's ones
-- you may open, and no one else sees them. Removing a project removes its
-- pins; a team project you may no longer open keeps the pin unseen.

create table core.tactics_project_pins (
  user_id uuid not null references core.profiles(id) on delete cascade,
  project_id uuid not null references core.tactics_projects(id) on delete cascade,
  pinned_at timestamptz not null default now(),
  primary key (user_id, project_id)
);
create index tactics_project_pins_project on core.tactics_project_pins (project_id);
alter table core.tactics_project_pins enable row level security;

-- The summary as in 20261123090000, now with the preview and your pin.
create or replace function internal.tactics_project_summary(project core.tactics_projects)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', project.id, 'name', project.name, 'kind', project.kind,
    'teamzone_team_id', project.teamzone_team_id,
    'team_name', (select team.name from core.teams team where team.id = project.teamzone_team_id),
    'board_count', coalesce(jsonb_array_length(project.document->'boards'), 0),
    'revision', project.revision, 'created_at', project.created_at, 'updated_at', project.updated_at,
    'preview', internal.tactics_board_preview(project.document, null),
    'pinned', exists (select 1 from core.tactics_project_pins pin where pin.user_id = auth.uid() and pin.project_id = project.id)
  )
$$;

-- Pins or unpins a project you may open.
create or replace function internal.set_tactics_project_pinned_for_actor(target_project_id uuid, pin boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare project core.tactics_projects;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  select * into project from core.tactics_projects where id = target_project_id;
  if project.id is null or internal.tactics_project_access(project) is null then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if pin then
    insert into core.tactics_project_pins (user_id, project_id) values (auth.uid(), project.id) on conflict do nothing;
  else
    delete from core.tactics_project_pins where user_id = auth.uid() and project_id = project.id;
  end if;
end;
$$;

create or replace function api.set_tactics_project_pinned(target_project_id uuid, pin boolean) returns void
language sql security invoker set search_path = '' as $$ select internal.set_tactics_project_pinned_for_actor(target_project_id, pin) $$;

revoke all on function internal.set_tactics_project_pinned_for_actor(uuid, boolean), api.set_tactics_project_pinned(uuid, boolean)
from public, anon, authenticated;
grant execute on function internal.set_tactics_project_pinned_for_actor(uuid, boolean), api.set_tactics_project_pinned(uuid, boolean)
to authenticated;
