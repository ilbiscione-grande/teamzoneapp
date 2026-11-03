-- Tacticsboard sold per person, plan item 8 (2026-11-03): without a trial or
-- a paid subscription the account is fully locked (decision 2026-11-02).
-- Every API function a person uses for their own Tacticsboard checks
-- webtool.tacticsboard first; the inner functions are unchanged.
--
-- Left open on purpose:
-- - shared links and folders (get_shared_tactics*), so what a locked
--   account has shared keeps working for others;
-- - live lessons once started (join, questions, chat, drawing, floor, end),
--   so a lesson in progress never stops; starting one is gated;
-- - taking things back: revoking a share link, unsharing from the library;
-- - the library's moderation (list/decide reports, for the admin).
-- TeamZone's own module flows (match plans, training passes) call internal
-- functions and are not affected.
--
-- supabase/tests/tacticsboard_write_gate.local.mjs checks that the latest
-- definition of every gated function still calls require_tacticsboard.

create function internal.require_tacticsboard()
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  -- The signed-out get the inner function's own not_signed_in.
  if auth.uid() is not null and not internal.actor_has_tacticsboard() then
    raise insufficient_privilege using message = 'tacticsboard_locked';
  end if;
end;
$$;
revoke all on function internal.require_tacticsboard() from public, anon, authenticated;
grant execute on function internal.require_tacticsboard() to authenticated;

create or replace function api.add_tactics_folder_project(target_folder_id uuid, target_project_id uuid) returns void
language sql security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.add_tactics_folder_project_for_actor(target_folder_id, target_project_id) $$;
create or replace function api.create_tactics_folder(folder_name text, folder_description text) returns jsonb
language sql security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.create_tactics_folder_for_actor(folder_name, folder_description) $$;
create or replace function api.create_tactics_folder_share_link(target_folder_id uuid) returns text
language sql security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.create_tactics_folder_share_link_for_actor(target_folder_id) $$;
create or replace function api.create_tactics_project(project_name text, project_kind text, target_team_id uuid, project_document jsonb) returns jsonb
language sql security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.create_tactics_project_for_actor(project_name, project_kind, target_team_id, project_document) $$;
create or replace function api.create_tactics_share_link(target_project_id uuid, target_board_id text) returns text
language sql security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.create_tactics_share_link_for_actor(target_project_id, target_board_id) $$;
create or replace function api.delete_tactics_folder(target_folder_id uuid) returns void
language sql security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.delete_tactics_folder_for_actor(target_folder_id) $$;
create or replace function api.delete_tactics_library_item(target_item_id uuid) returns void
language sql security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.delete_tactics_library_item_for_actor(target_item_id) $$;
create or replace function api.delete_tactics_project(target_project_id uuid) returns void
language sql security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.delete_tactics_project_for_actor(target_project_id) $$;
create or replace function api.delete_tactics_template(target_template_id uuid) returns void
language sql security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.delete_tactics_template_for_actor(target_template_id) $$;
create or replace function api.get_tactics_folder(target_folder_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.get_tactics_folder_for_actor(target_folder_id) $$;
create or replace function api.get_tactics_folder_share_link(target_folder_id uuid) returns text
language sql stable security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.get_tactics_folder_share_link_for_actor(target_folder_id) $$;
create or replace function api.get_tactics_library_item(target_item_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.get_tactics_library_item_for_actor(target_item_id) $$;
create or replace function api.get_tactics_project(target_project_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.get_tactics_project_for_actor(target_project_id) $$;
create or replace function api.get_tactics_shared_item(target_shared_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.get_tactics_shared_item_for_actor(target_shared_id) $$;
create or replace function api.get_tactics_template(target_template_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.get_tactics_template_for_actor(target_template_id) $$;
create or replace function api.get_tactics_version(target_version_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.get_tactics_version_for_actor(target_version_id) $$;
create or replace function api.list_my_tactics_clubs() returns jsonb
language sql stable security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.list_my_tactics_clubs_for_actor() $$;
create or replace function api.list_my_tactics_folders() returns jsonb
language sql stable security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.list_my_tactics_folders_for_actor() $$;
create or replace function api.list_my_tactics_library() returns jsonb
language sql stable security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.list_my_tactics_library_for_actor() $$;
create or replace function api.list_my_tactics_projects() returns jsonb
language sql stable security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.list_my_tactics_projects_for_actor() $$;
create or replace function api.list_my_tactics_templates() returns jsonb
language sql stable security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.list_my_tactics_templates_for_actor() $$;
create or replace function api.list_tactics_share_links(target_project_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.list_tactics_share_links_for_actor(target_project_id) $$;
create or replace function api.list_tactics_team_players(target_team_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.list_tactics_team_players_for_actor(target_team_id) $$;
create or replace function api.list_tactics_versions(target_project_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.list_tactics_versions_for_actor(target_project_id) $$;
create or replace function api.list_team_tactics_projects() returns jsonb
language sql stable security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.list_team_tactics_projects_for_actor() $$;
create or replace function api.order_tactics_folder(target_folder_id uuid, project_ids uuid[]) returns void
language sql security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.order_tactics_folder_for_actor(target_folder_id, project_ids) $$;
create or replace function api.publish_tactics_item(item_kind text, item_title text, item_details jsonb, item_document jsonb, from_project_id uuid, from_board_id text, target_club_id uuid) returns jsonb
language sql security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.publish_tactics_item_for_actor(item_kind, item_title, item_details, item_document, from_project_id, from_board_id, target_club_id) $$;
create or replace function api.remove_tactics_folder_project(target_folder_id uuid, target_project_id uuid) returns void
language sql security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.remove_tactics_folder_project_for_actor(target_folder_id, target_project_id) $$;
create or replace function api.report_tactics_shared_item(target_shared_id uuid, report_reason text) returns void
language sql security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.report_tactics_shared_item_for_actor(target_shared_id, report_reason) $$;
create or replace function api.restore_tactics_version(target_version_id uuid, expected_revision bigint) returns bigint
language sql security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.restore_tactics_version_for_actor(target_version_id, expected_revision) $$;
create or replace function api.save_tactics_host_notes(target_project_id uuid, target_board_id text, notes text) returns void
language sql security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.save_tactics_host_notes_for_actor(target_project_id, target_board_id, notes) $$;
create or replace function api.save_tactics_library_item(item_kind text, item_title text, item_details jsonb, item_document jsonb, from_project_id uuid, from_board_id text) returns jsonb
language sql security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.save_tactics_library_item_for_actor(item_kind, item_title, item_details, item_document, from_project_id, from_board_id) $$;
create or replace function api.save_tactics_project(target_project_id uuid, expected_revision bigint, project_name text, project_kind text, target_team_id uuid, project_document jsonb) returns bigint
language sql security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.save_tactics_project_for_actor(target_project_id, expected_revision, project_name, project_kind, target_team_id, project_document) $$;
create or replace function api.save_tactics_template(template_name text, template_kind text, template_document jsonb) returns uuid
language sql security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.save_tactics_template_for_actor(template_name, template_kind, template_document) $$;
create or replace function api.search_my_tactics_projects(search_text text, project_kind text, exercise_part text, game_phase text, age_class text, game_form text) returns jsonb
language sql stable security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.search_my_tactics_projects_for_actor(search_text, project_kind, exercise_part, game_phase, age_class, game_form) $$;
create or replace function api.search_tactics_shared_items(search_text text, item_kind text, exercise_part text, game_phase text, age_class text, game_form text, target_club_id uuid, only_favorites boolean, page integer) returns jsonb
language sql stable security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.search_tactics_shared_items_for_actor(search_text, item_kind, exercise_part, game_phase, age_class, game_form, target_club_id, only_favorites, page) $$;
create or replace function api.set_tactics_club_pick(target_club_id uuid, target_shared_id uuid, picked boolean) returns void
language sql security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.set_tactics_club_pick_for_actor(target_club_id, target_shared_id, picked) $$;
create or replace function api.set_tactics_favorite(target_shared_id uuid, marked boolean) returns void
language sql security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.set_tactics_favorite_for_actor(target_shared_id, marked) $$;
create or replace function api.set_tactics_leader_access(target_project_id uuid, access text) returns void
language sql security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.set_tactics_leader_access_for_actor(target_project_id, access) $$;
create or replace function api.set_tactics_project_folders(target_project_id uuid, folder_ids uuid[]) returns void
language sql security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.set_tactics_project_folders_for_actor(target_project_id, folder_ids) $$;
create or replace function api.set_tactics_project_pinned(target_project_id uuid, pin boolean) returns void
language sql security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.set_tactics_project_pinned_for_actor(target_project_id, pin) $$;
create or replace function api.share_tactics_library_item(target_item_id uuid, target_club_id uuid) returns jsonb
language sql security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.share_tactics_library_item_for_actor(target_item_id, target_club_id) $$;
create or replace function api.start_tactics_live(target_project_id uuid, guests_allowed boolean) returns jsonb
language sql security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.start_tactics_live_for_actor(target_project_id, guests_allowed) $$;
create or replace function api.update_tactics_folder(target_folder_id uuid, folder_name text, folder_description text) returns void
language sql security invoker set search_path = '' as
$$ select internal.require_tacticsboard(); select internal.update_tactics_folder_for_actor(target_folder_id, folder_name, folder_description) $$;

notify pgrst, 'reload schema';
