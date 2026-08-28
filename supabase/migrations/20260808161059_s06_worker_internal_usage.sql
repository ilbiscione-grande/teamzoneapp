grant usage on schema internal to service_role;
insert into internal.migration_provenance(migration_name,source_kind,source_reference) values('20260808161059_s06_worker_internal_usage','greenfield',null);
