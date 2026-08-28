create index publication_runtime_state_changed_by_idx
  on internal.publication_runtime_state(changed_by)
  where changed_by is not null;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values(
  '20260815105423_s09_boundary_advisor_hardening',
  'greenfield',
  'Cover internal publication kill-switch actor foreign key'
);
