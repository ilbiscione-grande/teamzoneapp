create function internal.actor_can_read_message_object(target_bucket text,target_key text)
returns boolean language sql stable security definer set search_path='' as $$
 select target_bucket='message-files' and exists(
  select 1 from core.file_objects file
  where file.bucket_id=target_bucket and file.object_key=target_key
    and file.state='active' and file.expires_at>now()
    and internal.actor_can_access_thread(file.thread_id,false));
$$;
revoke all on function internal.actor_can_read_message_object(text,text) from public,anon;
grant execute on function internal.actor_can_read_message_object(text,text) to authenticated;

drop policy message_files_select on storage.objects;
create policy message_files_select on storage.objects for select to authenticated using(
 bucket_id='message-files'
 and storage.allow_any_operation(array['object.get_authenticated_info','object.get_authenticated'])
 and internal.actor_can_read_message_object(bucket_id,name));

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260815072954_s06_fix_storage_read_authorization','greenfield',null);
