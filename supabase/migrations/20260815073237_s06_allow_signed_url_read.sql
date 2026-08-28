-- Signed URLs require SELECT permission on storage.objects. The previous
-- operation-name guard rejected the signing request before the existing
-- thread/file authorization helper could grant access.
drop policy if exists message_files_select on storage.objects;

create policy message_files_select
on storage.objects
for select
to authenticated
using (
  bucket_id = 'message-files'
  and internal.actor_can_read_message_object(bucket_id, name)
);
