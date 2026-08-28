-- HOME-04: one canonical priority/key contract for Home and Notification Center.

create function internal.attention_priority(kind text)
returns integer language sql immutable set search_path=''as $$
 select case
  when kind in('missing_attendance','callup_cancelled')then 10
  when kind in('pending_callup','callup_reminder','callup')then 20
  when kind in('event_today','next_event','event')then 30
  when kind in('unread_message','message')then 40
  else 50 end
$$;

create function internal.notification_attention_kind(event_type text)
returns text language sql immutable set search_path=''as $$
 select case
  when event_type like'callup.%.cancelled.%'then'callup_cancelled'
  when event_type like'callup.%.reminded.%'then'callup_reminder'
  when event_type like'callup.%'then'callup'
  when event_type like'event.%'then'event'
  when event_type='message.message.sent.v1'then'message'
  else'general'end
$$;

create function internal.notification_attention_key(outbox internal.notification_outbox)
returns text language sql immutable set search_path=''as $$
 select case
  when outbox.event_type like'callup.%'then'callup:'||outbox.aggregate_id::text
  when outbox.event_type like'event.%'then'event:'||outbox.aggregate_id::text
  when outbox.event_type='message.message.sent.v1'then'message:'||outbox.aggregate_id::text
  else outbox.aggregate_type||':'||outbox.aggregate_id::text end
$$;

create or replace function internal.list_notification_center_for_actor(page_before timestamptz default null,page_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path=''as $$
declare actor_id uuid:=auth.uid();
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 return jsonb_build_object('schema_version',3,'unread_count',(
  select count(*)from(
   select distinct on(internal.notification_attention_key(outbox))internal.notification_attention_key(outbox)
   from internal.notification_outbox outbox left join core.notification_receipts receipt
    on receipt.notification_id=outbox.id and receipt.profile_id=actor_id
   where outbox.recipient_profile_id=actor_id and receipt.notification_id is null
    and lower(outbox.event_type)not like'%watchpoint%'and lower(outbox.event_type)not like'%assistant%'
    and lower(outbox.event_type)not like'%assistant_coach%'and lower(outbox.event_type)not like'%ac_signal%'
   order by internal.notification_attention_key(outbox),outbox.created_at desc,outbox.id)unread),
  'items',coalesce((select jsonb_agg(limited order by priority,created_at desc,id)from(
   select * from(select distinct on(internal.notification_attention_key(outbox))outbox.id,outbox.event_type,
    internal.notification_attention_kind(outbox.event_type)category,
    internal.notification_attention_key(outbox)canonical_key,
    internal.attention_priority(internal.notification_attention_kind(outbox.event_type))priority,
    internal.notification_title(outbox.event_type)title,internal.notification_preview(outbox.event_type)preview,
    internal.notification_deep_link(outbox)deep_link,receipt.notification_id is null unread,outbox.created_at
   from internal.notification_outbox outbox left join core.notification_receipts receipt
    on receipt.notification_id=outbox.id and receipt.profile_id=actor_id
   where outbox.recipient_profile_id=actor_id and coalesce(receipt.state,'read')<>'dismissed'
    and(page_before is null or outbox.created_at<page_before)
    and lower(outbox.event_type)not like'%watchpoint%'and lower(outbox.event_type)not like'%assistant%'
    and lower(outbox.event_type)not like'%assistant_coach%'and lower(outbox.event_type)not like'%ac_signal%'
   order by internal.notification_attention_key(outbox),outbox.created_at desc,outbox.id)row_value
   order by priority,created_at desc,id limit greatest(1,least(page_limit,100)))limited),'[]'::jsonb));
end$$;

create or replace function internal.set_notification_state_for_actor(target_notification_id uuid,new_state text,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path=''as $$
declare actor_id uuid:=auth.uid();existing jsonb;target_row internal.notification_outbox%rowtype;new_revision bigint;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='notification.state.set.v1'and internal.command_deduplication.idempotency_key=set_notification_state_for_actor.idempotency_key;
 if existing is not null then return(existing->>'revision')::bigint;end if;
 select * into target_row from internal.notification_outbox where id=target_notification_id and recipient_profile_id=actor_id;
 if target_row.id is null or new_state not in('read','dismissed')then raise insufficient_privilege using message='not_found';end if;
 insert into core.notification_receipts(notification_id,profile_id,state)
 select outbox.id,actor_id,new_state from internal.notification_outbox outbox
 where outbox.recipient_profile_id=actor_id
  and internal.notification_attention_key(outbox)=internal.notification_attention_key(target_row)
 on conflict(notification_id,profile_id)do update set state=excluded.state,
  read_at=case when core.notification_receipts.state='read'then core.notification_receipts.read_at else now()end,
  updated_at=now(),revision=core.notification_receipts.revision+1;
 select max(receipt.revision)into new_revision from core.notification_receipts receipt
 join internal.notification_outbox outbox on outbox.id=receipt.notification_id
 where receipt.profile_id=actor_id and internal.notification_attention_key(outbox)=internal.notification_attention_key(target_row);
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'notification.state.set.v1',jsonb_build_object('revision',new_revision,
  'canonical_key',internal.notification_attention_key(target_row)));
 return new_revision;
end$$;

revoke all on function internal.attention_priority(text),internal.notification_attention_kind(text),
 internal.notification_attention_key(internal.notification_outbox)from public,anon,authenticated;
insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260827194321_home04_attention_model','greenfield','HOME-04 canonical keys, shared priority and deduplication');
notify pgrst,'reload schema';
