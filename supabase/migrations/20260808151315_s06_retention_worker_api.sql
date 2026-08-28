create function api.claim_expired_message_files(batch_size integer default 100)
returns table(id uuid,bucket_id text,object_key text) language sql security invoker set search_path='' as $$select * from internal.claim_expired_message_files(batch_size)$$;
create function api.finish_message_file_deletion(file_id uuid,succeeded boolean)
returns void language sql security invoker set search_path='' as $$select internal.finish_message_file_deletion(file_id,succeeded)$$;
create function api.apply_message_retention(batch_size integer default 500)
returns jsonb language sql security invoker set search_path='' as $$select internal.apply_message_retention(batch_size)$$;
revoke all on function api.claim_expired_message_files(integer),api.finish_message_file_deletion(uuid,boolean),api.apply_message_retention(integer) from public,anon,authenticated;
grant execute on function api.claim_expired_message_files(integer),api.finish_message_file_deletion(uuid,boolean),api.apply_message_retention(integer) to service_role;
insert into internal.migration_provenance(migration_name,source_kind,source_reference) values('20260808151315_s06_retention_worker_api','greenfield',null);
