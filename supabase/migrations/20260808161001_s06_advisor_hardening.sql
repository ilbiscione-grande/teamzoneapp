grant usage on schema api to service_role;

create policy retention_classes_no_direct_read on core.retention_classes for select to authenticated using(false);
create policy message_threads_no_direct_read on core.message_threads for select to authenticated using(false);
create policy thread_scopes_no_direct_read on core.thread_scopes for select to authenticated using(false);
create policy thread_participants_no_direct_read on core.thread_participants for select to authenticated using(false);
create policy messages_no_direct_read on core.messages for select to authenticated using(false);
create policy message_versions_no_direct_read on audit.message_versions for select to authenticated using(false);
create policy message_reads_no_direct_read on core.message_reads for select to authenticated using(false);
create policy thread_mutes_no_direct_read on core.thread_mutes for select to authenticated using(false);
create policy contact_controls_no_direct_read on core.contact_controls for select to authenticated using(false);
create policy message_reports_no_direct_read on core.message_reports for select to authenticated using(false);
create policy file_objects_no_direct_read on core.file_objects for select to authenticated using(false);
create policy leader_verifications_no_direct_read on core.leader_verifications for select to authenticated using(false);

create index message_threads_created_by_idx on core.message_threads(created_by);
create index thread_participants_profile_idx on core.thread_participants(profile_id);
create index thread_participants_club_idx on core.thread_participants(club_id);
create index thread_participants_person_club_idx on core.thread_participants(club_person_id,club_id);
create index messages_sender_idx on core.messages(sender_profile_id);
create index messages_acting_as_club_idx on core.messages(acting_as_person_id,club_id) where acting_as_person_id is not null;
create index message_versions_thread_idx on audit.message_versions(thread_id);
create index message_versions_actor_idx on audit.message_versions(actor_profile_id);
create index message_reads_profile_idx on core.message_reads(profile_id);
create index thread_mutes_profile_idx on core.thread_mutes(profile_id);
create index contact_controls_requester_idx on core.contact_controls(requester_profile_id);
create index contact_controls_target_idx on core.contact_controls(target_profile_id);
create index message_reports_thread_idx on core.message_reports(thread_id);
create index message_reports_message_idx on core.message_reports(message_id) where message_id is not null;
create index message_reports_reporter_idx on core.message_reports(reporter_profile_id);
create index message_reports_reported_idx on core.message_reports(reported_profile_id);
create index file_objects_club_idx on core.file_objects(club_id);
create index file_objects_message_idx on core.file_objects(message_id) where message_id is not null;
create index file_objects_owner_idx on core.file_objects(owner_profile_id);
create index leader_verifications_verified_by_idx on core.leader_verifications(verified_by);

insert into internal.migration_provenance(migration_name,source_kind,source_reference) values('20260808161001_s06_advisor_hardening','greenfield',null);
