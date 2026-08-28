-- MSG-06 explicit file authorization and auditable service-only moderation.

create table audit.message_moderation_actions(
 id uuid primary key default gen_random_uuid(),
 report_id uuid not null references core.message_reports(id),
 thread_id uuid not null references core.message_threads(id),
 message_id uuid references core.messages(id),
 reviewer_profile_id uuid references core.profiles(id),
 action text not null check(action in('dismiss','hide_message','close_thread','legal_hold')),
 reason text not null check(length(btrim(reason))between 3 and 500),
 evidence_hash text not null,
 created_at timestamptz not null default now(),
 unique(report_id,action)
);
alter table audit.message_moderation_actions enable row level security;
create policy message_moderation_actions_no_direct_read on audit.message_moderation_actions
for select to authenticated using(false);
create index message_moderation_actions_thread_idx on audit.message_moderation_actions(thread_id,created_at desc);
create trigger messages_private_update_invalidation after update of state,revision on core.messages
for each row execute function internal.broadcast_message_invalidation();
create trigger messages_inbox_update_invalidation after update of state,revision on core.messages
for each row execute function internal.broadcast_inbox_invalidation();

drop function api.list_message_files(uuid);
create function internal.list_message_files_for_actor(target_thread_id uuid)
returns table(id uuid,message_id uuid,original_name text,mime_type text,size_bytes bigint)
language sql stable security definer set search_path='' as $$
 select file.id,file.message_id,file.original_name,file.mime_type,file.size_bytes
 from core.file_objects file
 where file.thread_id=target_thread_id and file.state='active' and file.expires_at>now()
  and internal.actor_can_access_thread(file.thread_id,false)
 order by file.created_at,file.id;
$$;
create function api.list_message_files(thread_id uuid)
returns table(id uuid,message_id uuid,original_name text,mime_type text,size_bytes bigint)
language sql stable security invoker set search_path='' as
$$select * from internal.list_message_files_for_actor(thread_id)$$;

create function internal.authorize_message_file_for_actor(target_file_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare file_row core.file_objects%rowtype;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 select * into file_row from core.file_objects where id=target_file_id and state='active' and expires_at>now();
 if file_row.id is null or not internal.actor_can_access_thread(file_row.thread_id,false)
 then raise insufficient_privilege using message='not_found';end if;
 return jsonb_build_object(
  'file_id',file_row.id,
  'bucket_id',file_row.bucket_id,
  'object_key',file_row.object_key,
  'expires_in_seconds',120
 );
end;$$;

create function internal.resolve_message_report_for_service(target_report_id uuid,new_action text,new_reason text,
 reviewer_profile_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare report_row core.message_reports%rowtype;message_row core.messages%rowtype;next_thread_revision bigint;
 action_state text;action_id uuid;version_number bigint;
begin
 if current_user not in('postgres','service_role')then raise insufficient_privilege;end if;
 if reviewer_profile_id is null or new_action not in('dismiss','hide_message','close_thread','legal_hold')
  or length(btrim(coalesce(new_reason,'')))not between 3 and 500
 then raise invalid_parameter_value using message='invalid_moderation_action';end if;
 select * into report_row from core.message_reports where id=target_report_id for update;
 if report_row.id is null or report_row.state not in('open','reviewing')
 then raise invalid_parameter_value using message='report_not_reviewable';end if;
 select * into message_row from core.messages where id=report_row.message_id for update;
 select revision+1 into next_thread_revision from core.message_threads where id=report_row.thread_id for update;
 if new_action='hide_message' then
  if message_row.id is null then raise invalid_parameter_value using message='message_not_found';end if;
  select coalesce(max(message_revision),0)+1 into version_number from audit.message_versions where message_id=message_row.id;
  insert into audit.message_versions(message_id,thread_id,message_revision,body_snapshot,body_hash,action,actor_profile_id,reason_code)
  values(message_row.id,message_row.thread_id,version_number,message_row.body,
   encode(extensions.digest(message_row.body,'sha256'),'hex'),'moderated',reviewer_profile_id,'moderation');
  update core.messages set body='[moderated]',state='moderated',revised_at=now(),revision=next_thread_revision where id=message_row.id;
  update core.file_objects set state='withdrawn',expires_at=now(),revision=revision+1
   where message_id=message_row.id and state='active';
  update core.message_threads set revision=next_thread_revision where id=report_row.thread_id;
 elsif new_action='close_thread' then
  update core.message_threads set state='closed',closed_at=now(),revision=next_thread_revision where id=report_row.thread_id;
 elsif new_action='legal_hold' then
  update core.message_threads set state='legal_hold',closed_at=null,revision=next_thread_revision where id=report_row.thread_id;
 end if;
 action_state:=case when new_action='dismiss' then 'dismissed' when new_action='legal_hold' then 'legal_hold' else 'resolved'end;
 update core.message_reports set state=action_state,resolved_at=case when action_state='legal_hold' then null else now()end,
  revision=revision+1 where id=report_row.id;
 insert into audit.message_moderation_actions(report_id,thread_id,message_id,reviewer_profile_id,action,reason,evidence_hash)
 values(report_row.id,report_row.thread_id,report_row.message_id,reviewer_profile_id,new_action,btrim(new_reason),report_row.evidence_hash)
 returning id into action_id;
 return jsonb_build_object('report_id',report_row.id,'state',action_state,'action_id',action_id,
  'thread_revision',case when new_action='dismiss' then null else next_thread_revision end);
end;$$;

create function api.authorize_message_file(file_id uuid)
returns jsonb language sql stable security invoker set search_path='' as
$$select internal.authorize_message_file_for_actor(file_id)$$;
create function api.resolve_message_report(report_id uuid,action text,reason text,reviewer_profile_id uuid default null)
returns jsonb language sql security invoker set search_path='' as
$$select internal.resolve_message_report_for_service(report_id,action,reason,reviewer_profile_id)$$;

revoke all on table audit.message_moderation_actions from public,anon,authenticated;
revoke all on function internal.authorize_message_file_for_actor(uuid),
 internal.list_message_files_for_actor(uuid),api.list_message_files(uuid),
 internal.resolve_message_report_for_service(uuid,text,text,uuid),api.authorize_message_file(uuid),
 api.resolve_message_report(uuid,text,text,uuid)from public,anon,authenticated;
grant execute on function internal.authorize_message_file_for_actor(uuid),api.authorize_message_file(uuid)to authenticated;
grant execute on function internal.list_message_files_for_actor(uuid),api.list_message_files(uuid)to authenticated;
grant execute on function internal.resolve_message_report_for_service(uuid,text,text,uuid),
 api.resolve_message_report(uuid,text,text,uuid)to service_role;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260827154559_msg06_file_authorization_moderation','greenfield','MSG-06 explicit file authorization and service-only moderation');
notify pgrst,'reload schema';
