create table core.file_objects (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  thread_id uuid not null references core.message_threads(id) on delete cascade,
  message_id uuid references core.messages(id) on delete cascade,
  owner_profile_id uuid not null references core.profiles(id),
  bucket_id text not null default 'message-files' check(bucket_id='message-files'),
  object_key text not null unique,
  original_name text not null check(length(btrim(original_name)) between 1 and 160),
  mime_type text not null check(mime_type in ('image/jpeg','image/png','application/pdf')),
  size_bytes bigint not null check(size_bytes between 1 and 10485760),
  state text not null default 'staged' check(state in ('staged','active','withdrawn','deleting','deleted')),
  created_at timestamptz not null default now(),
  finalized_at timestamptz,
  expires_at timestamptz not null,
  revision bigint not null default 1 check(revision>0),
  check((state='active' and message_id is not null and finalized_at is not null) or state<>'active'),
  check((state='staged' and message_id is null) or state<>'staged')
);
create index file_objects_thread_state_idx on core.file_objects(thread_id,state);
create index file_objects_expiry_idx on core.file_objects(expires_at,state) where state in ('staged','active','withdrawn');
alter table core.file_objects enable row level security;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('message-files','message-files',false,10485760,array['image/jpeg','image/png','application/pdf'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

grant execute on function internal.actor_can_access_thread(uuid,boolean) to authenticated;

create policy message_files_insert on storage.objects for insert to authenticated with check(
  bucket_id='message-files' and owner_id=(select auth.uid()::text) and exists(
    select 1 from core.file_objects file where file.object_key=storage.objects.name and file.bucket_id=storage.objects.bucket_id
      and file.owner_profile_id=(select auth.uid()) and file.state='staged' and file.expires_at>now()
      and internal.actor_can_access_thread(file.thread_id,true)
  )
);
create policy message_files_select on storage.objects for select to authenticated using(
  bucket_id='message-files' and storage.allow_any_operation(array['object.get_authenticated_info','object.get_authenticated']) and exists(
    select 1 from core.file_objects file where file.object_key=storage.objects.name and file.bucket_id=storage.objects.bucket_id
      and file.state='active' and file.expires_at>now() and internal.actor_can_access_thread(file.thread_id,false)
  )
);
create policy message_files_staged_delete on storage.objects for delete to authenticated using(
  bucket_id='message-files' and owner_id=(select auth.uid()::text) and exists(
    select 1 from core.file_objects file where file.object_key=storage.objects.name and file.owner_profile_id=(select auth.uid()) and file.state='staged'
  )
);

create function internal.stage_message_file_for_actor(target_thread_id uuid,new_name text,new_mime_type text,new_size_bytes bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare file_id uuid:=gen_random_uuid(); target_club uuid; object_key text;
begin
 if not internal.actor_can_access_thread(target_thread_id,true) then raise insufficient_privilege using message='not_found'; end if;
 if new_mime_type not in ('image/jpeg','image/png','application/pdf') or new_size_bytes not between 1 and 10485760 or length(btrim(new_name)) not between 1 and 160 then raise invalid_parameter_value using message='invalid_file'; end if;
 select club_id into target_club from core.thread_participants where thread_id=target_thread_id and profile_id=auth.uid() and state='active';
 object_key:=target_club::text||'/'||target_thread_id::text||'/'||auth.uid()::text||'/'||file_id::text;
 insert into core.file_objects(id,club_id,thread_id,owner_profile_id,object_key,original_name,mime_type,size_bytes,expires_at)
 values(file_id,target_club,target_thread_id,auth.uid(),object_key,btrim(new_name),new_mime_type,new_size_bytes,now()+interval '24 hours');
 return jsonb_build_object('file_id',file_id,'bucket_id','message-files','object_key',object_key,'expires_at',now()+interval '24 hours');
end; $$;

create function internal.send_message_with_files_for_actor(target_thread_id uuid,new_body text,staged_file_ids uuid[],idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; target_message uuid; expected_count integer; valid_count integer;
begin
 if staged_file_ids is null or cardinality(staged_file_ids)>10 or array_position(staged_file_ids,null) is not null then raise invalid_parameter_value using message='invalid_files'; end if;
 select count(distinct value) into expected_count from unnest(staged_file_ids)value;
 select count(*) into valid_count from core.file_objects file join storage.objects object on object.bucket_id=file.bucket_id and object.name=file.object_key
 where file.id=any(staged_file_ids) and file.thread_id=target_thread_id and file.owner_profile_id=auth.uid() and file.state='staged' and file.expires_at>now()
   and (object.metadata->>'size')::bigint=file.size_bytes;
 if valid_count<>expected_count then raise invalid_parameter_value using message='invalid_files'; end if;
 result:=internal.send_message_for_actor(target_thread_id,new_body,idempotency_key);
 target_message:=(result->>'message_id')::uuid;
 update core.file_objects set message_id=target_message,state='active',finalized_at=now(),expires_at=now()+interval '365 days',revision=revision+1 where id=any(staged_file_ids);
 return result||jsonb_build_object('file_count',expected_count);
end; $$;

drop function api.send_message(uuid,text,uuid);
create function api.send_message(thread_id uuid,body text,staged_file_ids uuid[],idempotency_key uuid) returns jsonb language sql security invoker set search_path='' as $$select internal.send_message_with_files_for_actor(thread_id,body,staged_file_ids,idempotency_key)$$;
revoke all on function api.send_message(uuid,text,uuid[],uuid) from public,anon;
grant execute on function api.send_message(uuid,text,uuid[],uuid) to authenticated;

create function api.stage_message_file(thread_id uuid,file_name text,mime_type text,size_bytes bigint) returns jsonb language sql security invoker set search_path='' as $$select internal.stage_message_file_for_actor(thread_id,file_name,mime_type,size_bytes)$$;
revoke all on function api.stage_message_file(uuid,text,text,bigint) from public,anon;
grant execute on function api.stage_message_file(uuid,text,text,bigint) to authenticated;

create function internal.claim_expired_message_files(batch_size integer default 100)
returns table(id uuid,bucket_id text,object_key text) language plpgsql security definer set search_path='' as $$
begin
 return query with claimed as (select file.id from core.file_objects file where file.state in ('staged','active','withdrawn') and file.expires_at<=now() order by file.expires_at,file.id for update skip locked limit greatest(1,least(batch_size,500)))
 update core.file_objects file set state='deleting',revision=revision+1 from claimed where file.id=claimed.id returning file.id,file.bucket_id,file.object_key;
end; $$;
create function internal.finish_message_file_deletion(target_file_id uuid,succeeded boolean)
returns void language plpgsql security definer set search_path='' as $$begin update core.file_objects set state=case when succeeded then 'deleted' else 'withdrawn' end,expires_at=case when succeeded then expires_at else now()+interval '1 hour' end,revision=revision+1 where id=target_file_id and state='deleting';end$$;
create function internal.apply_message_retention(batch_size integer default 500)
returns jsonb language plpgsql security definer set search_path='' as $$
declare version_count integer; message_count integer;
begin
 with target as (select id from audit.message_versions where body_snapshot is not null and erase_body_at<=now() order by erase_body_at limit greatest(1,least(batch_size,1000)) for update skip locked)
 update audit.message_versions version set body_snapshot=null from target where version.id=target.id; get diagnostics version_count=row_count;
 with target as (select id from core.messages where expires_at<=now() and state<>'moderated' order by expires_at limit greatest(1,least(batch_size,1000)) for update skip locked)
 update core.messages message set body='[expired]',state='moderated',revision=revision+1 from target where message.id=target.id; get diagnostics message_count=row_count;
 return jsonb_build_object('versions_erased',version_count,'messages_erased',message_count);
end; $$;
revoke all on function internal.stage_message_file_for_actor(uuid,text,text,bigint),internal.send_message_with_files_for_actor(uuid,text,uuid[],uuid),internal.claim_expired_message_files(integer),internal.finish_message_file_deletion(uuid,boolean),internal.apply_message_retention(integer) from public,anon,authenticated;
grant execute on function internal.stage_message_file_for_actor(uuid,text,text,bigint),internal.send_message_with_files_for_actor(uuid,text,uuid[],uuid) to authenticated;
grant execute on function internal.claim_expired_message_files(integer),internal.finish_message_file_deletion(uuid,boolean),internal.apply_message_retention(integer) to service_role;

create function internal.broadcast_message_invalidation() returns trigger language plpgsql security definer set search_path='' as $$
begin perform realtime.send(jsonb_build_object('thread_id',new.thread_id,'revision',new.revision),'invalidate','message:thread:'||new.thread_id::text,true);return null;end$$;
create trigger messages_private_invalidation after insert on core.messages for each row execute function internal.broadcast_message_invalidation();
create policy teamzone_message_broadcast_select on realtime.messages for select to authenticated using(
 realtime.messages.extension='broadcast' and (select realtime.topic()) ~ '^message:thread:[0-9a-fA-F-]{36}$'
 and internal.actor_can_access_thread(substring((select realtime.topic()) from '^message:thread:([0-9a-fA-F-]{36})$')::uuid,false)
);

insert into internal.migration_provenance(migration_name,source_kind,source_reference) values('20260808141138_s06_private_files_retention_realtime','greenfield',null);
notify pgrst,'reload schema';
