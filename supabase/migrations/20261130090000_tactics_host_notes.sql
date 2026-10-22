-- Webtools Tacticsboard: the presenter's own notes, one per board, for
-- what to say in a live lesson. They are kept beside the project's
-- document, never in it: participants, shared links and templates read the
-- document only, so the notes reach nobody but the project's owner.

alter table core.tactics_projects add column host_notes jsonb not null default '{}'::jsonb
  check (jsonb_typeof(host_notes) = 'object' and pg_column_size(host_notes) <= 400000);

-- The owner's project, now with the notes.
create or replace function internal.get_tactics_project_for_actor(target_project_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare project core.tactics_projects;
begin
  select * into project from core.tactics_projects where id = target_project_id;
  if project.id is null or project.owner_id is distinct from auth.uid() then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return internal.tactics_project_summary(project) || jsonb_build_object('document', project.document, 'host_notes', project.host_notes);
end;
$$;

-- One board's notes; empty removes them. At most 5000 characters each.
create or replace function internal.save_tactics_host_notes_for_actor(target_project_id uuid, target_board_id text, notes text)
returns void language plpgsql security definer set search_path = '' as $$
declare text_now text := coalesce(notes, '');
begin
  if length(coalesce(target_board_id, '')) not between 1 and 80 or length(text_now) > 5000 then
    raise invalid_parameter_value using message = 'invalid_notes';
  end if;
  update core.tactics_projects
  set host_notes = case when btrim(text_now) = '' then host_notes - target_board_id
                        else host_notes || jsonb_build_object(target_board_id, text_now) end
  where id = target_project_id and owner_id = auth.uid();
  if not found then raise insufficient_privilege using message = 'not_found'; end if;
end;
$$;

create or replace function api.save_tactics_host_notes(target_project_id uuid, target_board_id text, notes text) returns void
language sql security invoker set search_path = '' as $$ select internal.save_tactics_host_notes_for_actor(target_project_id, target_board_id, notes) $$;

revoke all on function internal.save_tactics_host_notes_for_actor(uuid, text, text), api.save_tactics_host_notes(uuid, text, text)
from public, anon, authenticated;
grant execute on function internal.save_tactics_host_notes_for_actor(uuid, text, text), api.save_tactics_host_notes(uuid, text, text)
to authenticated;
