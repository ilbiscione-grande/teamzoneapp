create function internal.actor_can_upload_message_object(target_bucket text,target_key text)
returns boolean language sql stable security definer set search_path='' as $$
 select target_bucket='message-files' and exists(
  select 1 from core.file_objects file
  where file.bucket_id=target_bucket and file.object_key=target_key
    and file.owner_profile_id=auth.uid() and file.state='staged' and file.expires_at>now()
    and internal.actor_can_access_thread(file.thread_id,true));
$$;
revoke all on function internal.actor_can_upload_message_object(text,text) from public,anon;
grant execute on function internal.actor_can_upload_message_object(text,text) to authenticated;

drop policy message_files_insert on storage.objects;
create policy message_files_insert on storage.objects for insert to authenticated with check(
 bucket_id='message-files'
 and owner_id=(select auth.uid()::text)
 and internal.actor_can_upload_message_object(bucket_id,name));

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260815070844_s06_fix_storage_upload_authorization','greenfield',null);
