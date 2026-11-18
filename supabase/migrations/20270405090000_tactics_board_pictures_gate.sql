-- Bild av tavlan (20270328090000) came after Tacticsboard's lock
-- (20270206090000) and was left outside it: saving a project's board pictures
-- is part of a person's own Tacticsboard, like saving the project, so it now
-- needs a trial or subscription too. The inner function is unchanged, and the
-- editor already ignores a picture that cannot be saved.

create or replace function api.save_tactics_board_pictures(target_project_id uuid, pictures jsonb)
returns integer language sql security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.save_tactics_board_pictures_for_actor(target_project_id, pictures) $$;

notify pgrst, 'reload schema';
