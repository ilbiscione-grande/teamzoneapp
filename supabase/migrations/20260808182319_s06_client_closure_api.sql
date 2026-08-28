create function api.list_message_files(thread_id uuid)
returns table(id uuid,message_id uuid,original_name text,mime_type text,size_bytes bigint,object_key text)
language sql stable security invoker set search_path='' as $$
 select file.id,file.message_id,file.original_name,file.mime_type,file.size_bytes,file.object_key
 from core.file_objects file
 where file.thread_id=list_message_files.thread_id and file.state='active' and file.expires_at>now()
   and internal.actor_can_access_thread(file.thread_id,false)
 order by file.created_at;
$$;

create function api.list_contact_requests()
returns table(id uuid,requester_name text,reason_code text,request_text text,expires_at timestamptz)
language sql stable security definer set search_path='' as $$
 select request.id,profile.display_name,request.reason_code,request.request_text,request.expires_at
 from core.contact_controls request join core.profiles profile on profile.id=request.requester_profile_id
 where request.target_profile_id=auth.uid() and request.control_type='request' and request.state='pending' and request.expires_at>now()
 order by request.created_at desc;
$$;

create function api.list_notification_center(page_limit integer default 50)
returns table(id uuid,event_type text,aggregate_type text,aggregate_id uuid,created_at timestamptz)
language sql stable security definer set search_path='' as $$
 select outbox.id,outbox.event_type,outbox.aggregate_type,outbox.aggregate_id,outbox.created_at
 from internal.notification_outbox outbox
 where outbox.recipient_profile_id=auth.uid()
 order by outbox.created_at desc limit greatest(1,least(page_limit,100));
$$;

create function api.block_profile(target_profile_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or target_profile_id is null or target_profile_id=auth.uid() then raise insufficient_privilege using message='not_found'; end if;
 insert into core.contact_controls(requester_profile_id,target_profile_id,control_type,state)
 values(auth.uid(),target_profile_id,'block','active') on conflict do nothing;
 update core.message_threads thread set state='closed',closed_at=now(),revision=revision+1
 where thread.thread_type in ('direct','cross_club_direct') and exists(
  select 1 from core.thread_participants a join core.thread_participants b on b.thread_id=a.thread_id
  where a.thread_id=thread.id and a.profile_id=auth.uid() and b.profile_id=target_profile_id);
end$$;

revoke all on function api.list_message_files(uuid),api.list_contact_requests(),api.list_notification_center(integer),api.block_profile(uuid) from public,anon;
grant execute on function api.list_message_files(uuid),api.list_contact_requests(),api.list_notification_center(integer),api.block_profile(uuid) to authenticated;
insert into internal.migration_provenance(migration_name,source_kind,source_reference) values('20260808182319_s06_client_closure_api','greenfield',null);
notify pgrst,'reload schema';
