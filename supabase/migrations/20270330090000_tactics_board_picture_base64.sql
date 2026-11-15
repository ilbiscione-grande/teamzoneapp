-- Rättning av 20270328090000 (2026-11-15): Postgres breaks base64 into lines
-- of 76 characters, and the app's decoder refuses the line breaks, so the
-- picture never showed. The data now comes on one line.

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
  select jsonb_build_object('media_type', picture.media_type, 'data', translate(encode(picture.picture, 'base64'), E'\n', ''),
      'width', picture.width, 'height', picture.height, 'updated_at', picture.updated_at)
    into result
  from core.tactics_board_pictures picture
  where picture.project_id = block.board_ref and picture.board_id = block.board_id;
  return result;
end;
$$;

notify pgrst, 'reload schema';
