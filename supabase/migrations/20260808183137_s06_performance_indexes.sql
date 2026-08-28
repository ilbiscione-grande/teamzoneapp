create index message_threads_retention_class_idx on core.message_threads(retention_class);
create index thread_scopes_team_club_idx on core.thread_scopes(team_id,club_id) where team_id is not null;
insert into internal.migration_provenance(migration_name,source_kind,source_reference) values('20260808183137_s06_performance_indexes','greenfield',null);
