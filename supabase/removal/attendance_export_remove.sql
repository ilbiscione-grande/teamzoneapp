-- Removes the temporary attendance export (laget.se) completely.
-- Run only after the app hooks have been removed (see
-- docs/implementation/attendance_export_laget_se.md, "Borttagning").
-- Touches no core tables: core attendance, events and people are unaffected.

drop function if exists api.attendance_export_get_team_integration(uuid, text);
drop function if exists api.attendance_export_set_team_integration(uuid, text, boolean, text, bigint);
drop function if exists api.attendance_export_save_member_link(uuid, text, uuid, text, text, text, bigint);
drop function if exists api.attendance_export_delete_member_link(uuid, text, uuid, bigint);
drop function if exists api.attendance_export_get_context(uuid, uuid, text);
drop function if exists api.attendance_export_set_activity_link(uuid, uuid, text, text, bigint);
drop function if exists api.attendance_export_record(uuid, uuid, text, text, text, jsonb, boolean, text, text);
drop function if exists api.attendance_export_request_sync(uuid, uuid, text, jsonb, jsonb, boolean);
drop function if exists api.attendance_export_approve_sync(uuid, text);
drop function if exists api.attendance_export_cancel_sync(uuid);
drop function if exists api.attendance_export_agent_heartbeat(boolean, text);
drop function if exists api.attendance_export_agent_claim_job();
drop function if exists api.attendance_export_agent_report_preview(uuid, jsonb, text);
drop function if exists api.attendance_export_agent_release_job(uuid, text);
drop function if exists api.attendance_export_agent_report_result(uuid, boolean, text, jsonb, jsonb);
drop function if exists api.attendance_export_agent_report_located(uuid, text);
drop function if exists api.attendance_export_agent_report_not_found(uuid, text, jsonb);
drop schema if exists attendance_export cascade;
-- audit.command_events rows of type 'attendance_export.%' are kept as history.
notify pgrst, 'reload schema';
