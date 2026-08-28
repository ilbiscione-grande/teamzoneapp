-- Explicit deny policies make the API-only access model visible to tooling.
create policy development_plans_no_direct_access on core.development_plans
  for all to authenticated using(false) with check(false);
create policy development_actions_no_direct_access on core.development_actions
  for all to authenticated using(false) with check(false);
create policy signal_definitions_no_direct_access on core.signal_definitions
  for all to authenticated using(false) with check(false);

create index development_plans_team_club_fk_idx on core.development_plans(team_id,club_id);
create index development_plans_subject_club_fk_idx on core.development_plans(subject_club_person_id,club_id)
  where subject_club_person_id is not null;
create index development_plans_created_by_idx on core.development_plans(created_by);
create index development_plans_updated_by_idx on core.development_plans(updated_by);
create index development_actions_plan_club_fk_idx on core.development_actions(plan_id,club_id);
create index development_actions_created_by_idx on core.development_actions(created_by);
create index development_actions_updated_by_idx on core.development_actions(updated_by);

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260815093928_s08_advisor_hardening','greenfield','Explicit API-only deny policies and FK indexes');
