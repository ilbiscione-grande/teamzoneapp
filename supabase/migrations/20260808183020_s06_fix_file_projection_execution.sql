create or replace function api.list_message_files(thread_id uuid)
returns table(id uuid,message_id uuid,original_name text,mime_type text,size_bytes bigint,object_key text)
language sql stable security definer set search_path='' as $$
 select file.id,file.message_id,file.original_name,file.mime_type,file.size_bytes,file.object_key
 from core.file_objects file
 where file.thread_id=list_message_files.thread_id and file.state='active' and file.expires_at>now()
   and internal.actor_can_access_thread(file.thread_id,false)
 order by file.created_at;
$$;
revoke all on function api.list_message_files(uuid) from public,anon;
grant execute on function api.list_message_files(uuid) to authenticated;
insert into internal.migration_provenance(migration_name,source_kind,source_reference) values('20260808183020_s06_fix_file_projection_execution','greenfield',null);
notify pgrst,'reload schema';
