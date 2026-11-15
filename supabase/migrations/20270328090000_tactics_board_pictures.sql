-- Bild av tavlan (2026-11-15): Tacticsboard saves a small picture of each
-- board's first frame, drawn by the editor itself (OffscreenBoard), and a
-- training session shows it for an exercise's linked board. The picture is
-- a WebP or PNG of at most 200 kB, kept per project and board; it goes with
-- the project when the project is deleted.

create table core.tactics_board_pictures (
  project_id uuid not null references core.tactics_projects(id) on delete cascade,
  board_id text not null check (length(board_id) between 1 and 100),
  media_type text not null check (media_type in ('image/webp', 'image/png')),
  picture bytea not null check (octet_length(picture) <= 204800),
  width integer not null check (width between 16 and 2000),
  height integer not null check (height between 16 and 2000),
  updated_at timestamptz not null default now(),
  primary key (project_id, board_id)
);

alter table core.tactics_board_pictures enable row level security;
revoke all on core.tactics_board_pictures from public, anon, authenticated;

-- Saves the project's board pictures, replacing those of the same boards and
-- dropping those of boards the project no longer has. pictures:
-- [{board_id, media_type, data (base64), width, height}], at most 60. Who may
-- edit the project may save them.
create or replace function internal.save_tactics_board_pictures_for_actor(target_project_id uuid, pictures jsonb)
returns integer language plpgsql security definer set search_path = '' as $$
declare project core.tactics_projects; item jsonb; saved integer := 0; image bytea;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  select * into project from core.tactics_projects where id = target_project_id;
  if coalesce(internal.tactics_project_access(project), '') not in ('owner', 'edit') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if jsonb_typeof(pictures) <> 'array' or jsonb_array_length(pictures) > 60 then
    raise invalid_parameter_value using message = 'invalid_pictures';
  end if;
  for item in select value from jsonb_array_elements(pictures) loop
    if coalesce(item->>'media_type', '') not in ('image/webp', 'image/png')
      or length(coalesce(item->>'board_id', '')) not between 1 and 100
      or not exists (select 1 from jsonb_array_elements(
        case when jsonb_typeof(project.document->'boards') = 'array' then project.document->'boards' else '[]'::jsonb end) board
        where board->>'id' = item->>'board_id') then
      raise invalid_parameter_value using message = 'invalid_pictures';
    end if;
    begin
      image := decode(item->>'data', 'base64');
    exception when others then
      raise invalid_parameter_value using message = 'invalid_pictures';
    end;
    insert into core.tactics_board_pictures(project_id, board_id, media_type, picture, width, height)
    values (project.id, item->>'board_id', item->>'media_type', image, (item->>'width')::integer, (item->>'height')::integer)
    on conflict (project_id, board_id) do update set media_type = excluded.media_type, picture = excluded.picture,
      width = excluded.width, height = excluded.height, updated_at = now();
    saved := saved + 1;
  end loop;
  delete from core.tactics_board_pictures picture where picture.project_id = project.id
    and not exists (select 1 from jsonb_array_elements(
      case when jsonb_typeof(project.document->'boards') = 'array' then project.document->'boards' else '[]'::jsonb end) board
      where board->>'id' = picture.board_id);
  return saved;
end;
$$;

-- The picture of a training exercise's linked board, for whoever may read
-- the session (as api.open_training_block_board): {media_type, data
-- (base64), width, height, updated_at}, or null without one. Only boards
-- from a project; the library's keep the app's own drawing for now.
create or replace function internal.training_block_board_picture_for_actor(target_block_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare block core.training_blocks; event_row core.events; result jsonb;
begin
  select * into block from core.training_blocks where id = target_block_id;
  if block.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  event_row := internal.training_session_event(block.event_id);
  if not internal.training_session_can_edit(event_row)
    and not exists (select 1 from core.training_sessions session where session.event_id = event_row.id and session.published) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if block.board_source is distinct from 'mine' then return null; end if;
  select jsonb_build_object('media_type', picture.media_type, 'data', encode(picture.picture, 'base64'),
      'width', picture.width, 'height', picture.height, 'updated_at', picture.updated_at)
    into result
  from core.tactics_board_pictures picture
  where picture.project_id = block.board_ref and picture.board_id = block.board_id;
  return result;
end;
$$;

create or replace function api.save_tactics_board_pictures(target_project_id uuid, pictures jsonb)
returns integer language sql security invoker set search_path = '' as $$
  select internal.save_tactics_board_pictures_for_actor(target_project_id, pictures) $$;
create or replace function api.training_block_board_picture(target_block_id uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select internal.training_block_board_picture_for_actor(target_block_id) $$;

revoke all on function
  internal.save_tactics_board_pictures_for_actor(uuid, jsonb),
  internal.training_block_board_picture_for_actor(uuid),
  api.save_tactics_board_pictures(uuid, jsonb),
  api.training_block_board_picture(uuid)
from public, anon, authenticated;
grant execute on function
  internal.save_tactics_board_pictures_for_actor(uuid, jsonb),
  internal.training_block_board_picture_for_actor(uuid),
  api.save_tactics_board_pictures(uuid, jsonb),
  api.training_block_board_picture(uuid)
to authenticated;

notify pgrst, 'reload schema';
