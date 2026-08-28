create or replace function internal.recall_message_for_actor(target_message_id uuid,expected_revision bigint,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare
  actor_id uuid:=auth.uid(); message_row core.messages%rowtype; next_version bigint;
  next_thread_revision bigint; existing jsonb;
begin
 select result into existing from internal.command_deduplication
 where actor_profile_id=actor_id and command_type='message.message.recalled.v1'
   and internal.command_deduplication.idempotency_key=recall_message_for_actor.idempotency_key;
 if existing is not null then return (existing->>'revision')::bigint; end if;
 select * into message_row from core.messages where id=target_message_id for update;
 if message_row.id is null or message_row.sender_profile_id<>actor_id or message_row.state<>'sent'
 or message_row.revision<>expected_revision or message_row.created_at<now()-interval '15 minutes'
 or not internal.actor_can_access_thread(message_row.thread_id,true) then raise insufficient_privilege using message='not_found'; end if;
 select revision+1 into next_thread_revision from core.message_threads where id=message_row.thread_id for update;
 select coalesce(max(message_revision),0)+1 into next_version from audit.message_versions where message_id=target_message_id;
 insert into audit.message_versions(message_id,thread_id,message_revision,body_snapshot,body_hash,action,actor_profile_id)
 values(message_row.id,message_row.thread_id,next_version,message_row.body,encode(extensions.digest(message_row.body,'sha256'),'hex'),'recalled',actor_id);
 update core.messages set body='[recalled]',state='recalled',recalled_at=now(),revision=next_thread_revision where id=message_row.id;
 update core.message_threads set revision=next_thread_revision where id=message_row.thread_id;
 update core.file_objects set state='withdrawn',expires_at=now(),revision=revision+1 where message_id=message_row.id and state='active';
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'message.message.recalled.v1',jsonb_build_object('revision',next_thread_revision));
 return next_thread_revision;
end$$;

create or replace function internal.report_message_for_actor(target_message_id uuid,reason_code text,idempotency_key uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); message_row core.messages%rowtype; report_id uuid:=gen_random_uuid(); existing jsonb;
begin
 select result into existing from internal.command_deduplication
 where actor_profile_id=actor_id and command_type='message.message.reported.v1'
   and internal.command_deduplication.idempotency_key=report_message_for_actor.idempotency_key;
 if existing is not null then return (existing->>'report_id')::uuid; end if;
 select * into message_row from core.messages where id=target_message_id;
 if message_row.id is null or not internal.actor_can_access_thread(message_row.thread_id,false)
 or message_row.sender_profile_id=actor_id or reason_code not in ('harassment','sexual_content','threat','spam','other')
 then raise insufficient_privilege using message='not_found'; end if;
 insert into core.message_reports(id,thread_id,message_id,reporter_profile_id,reported_profile_id,reason_code,evidence_hash)
 values(report_id,message_row.thread_id,message_row.id,actor_id,message_row.sender_profile_id,reason_code,encode(extensions.digest(message_row.body,'sha256'),'hex'));
 insert into core.contact_controls(requester_profile_id,target_profile_id,control_type,state)
 values(actor_id,message_row.sender_profile_id,'block','active') on conflict do nothing;
 update core.message_threads set state='closed',closed_at=now(),revision=revision+1
 where id=message_row.thread_id and thread_type in ('direct','cross_club_direct');
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'message.message.reported.v1',jsonb_build_object('report_id',report_id));
 return report_id;
end$$;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260815073924_s06_fix_recall_thread_revision','greenfield',null);
