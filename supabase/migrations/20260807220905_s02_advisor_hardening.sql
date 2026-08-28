create policy roster_invites_no_direct_select
on core.roster_invites for select to authenticated using (false);

create policy transfer_approvals_no_direct_select
on audit.transfer_approvals for select to authenticated using (false);

create index persons_created_by_idx on core.persons(created_by);
create index team_assignments_team_club_idx on core.team_assignments(team_id,club_id);
create index team_assignments_person_club_idx on core.team_assignments(club_person_id,club_id);
create index team_assignments_created_by_idx on core.team_assignments(created_by);
create index team_assignments_ended_by_idx on core.team_assignments(ended_by);
create index play_eligibilities_team_club_idx on core.play_eligibilities(team_id,club_id);
create index play_eligibilities_person_club_idx on core.play_eligibilities(club_person_id,club_id);
create index play_eligibilities_source_club_idx on core.play_eligibilities(source_club_id);
create index play_eligibilities_created_by_idx on core.play_eligibilities(created_by);
create index guardian_relations_guardian_club_idx on core.guardian_relations(guardian_person_id,club_id);
create index guardian_relations_created_by_idx on core.guardian_relations(created_by);
create index roster_invites_person_club_idx on core.roster_invites(club_person_id,club_id);
create index roster_invites_consumed_by_idx on core.roster_invites(consumed_by);
create index roster_invites_created_by_idx on core.roster_invites(created_by);
create index transfer_cases_source_team_club_idx on core.transfer_cases(source_team_id,source_club_id);
create index transfer_cases_source_person_club_idx on core.transfer_cases(source_club_person_id,source_club_id);
create index transfer_cases_target_team_club_idx on core.transfer_cases(target_team_id,target_club_id);
create index transfer_cases_completed_person_club_idx on core.transfer_cases(completed_club_person_id,target_club_id);
create index transfer_cases_created_by_idx on core.transfer_cases(created_by);
create index transfer_approvals_actor_idx on audit.transfer_approvals(actor_profile_id);

insert into internal.migration_provenance(migration_name)
values('20260807220905_s02_advisor_hardening');
