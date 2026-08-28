do $$ declare definition text;
begin
 select pg_get_functiondef(procedure.oid) into definition from pg_proc procedure join pg_namespace namespace on namespace.oid=procedure.pronamespace where namespace.nspname='internal' and procedure.proname='finish_notification_attempt';
 execute replace(definition,'encode(digest(provider_reference,''sha256''),''hex'')','encode(extensions.digest(provider_reference,''sha256''),''hex'')');
end $$;
insert into internal.migration_provenance(migration_name,source_kind,source_reference) values('20260808075116_s04_provider_ref_hash_schema','greenfield',null);
