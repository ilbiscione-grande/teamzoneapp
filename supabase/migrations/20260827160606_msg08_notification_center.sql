-- MSG-08: account-synced, data-minimized notification center without Watchpoints or AC signals.

create table core.notification_receipts(
 notification_id uuid not null references internal.notification_outbox(id) on delete cascade,
 profile_id uuid not null references core.profiles(id),
 state text not null default 'read' check(state in('read','dismissed')),
 read_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 revision bigint not null default 1 check(revision>0),primary key(notification_id,profile_id)
);
alter table core.notification_receipts enable row level security;
create policy notification_receipts_no_direct_access on core.notification_receipts
 for all to authenticated using(false)with check(false);
create index notification_receipts_profile_state_idx on core.notification_receipts(profile_id,state,updated_at desc);

create function internal.broadcast_notification_center_invalidation()
returns trigger language plpgsql security definer set search_path=''as $$
declare target_profile_id uuid:=case when tg_table_name='notification_outbox'then new.recipient_profile_id else new.profile_id end;
begin
 if target_profile_id is not null then
  perform realtime.send('{}'::jsonb,'invalidate','notification:center:'||target_profile_id::text,true);
 end if;
 return null;
end$$;
create trigger notification_outbox_center_invalidation after insert on internal.notification_outbox
 for each row execute function internal.broadcast_notification_center_invalidation();
create trigger notification_receipts_center_invalidation after insert or update on core.notification_receipts
 for each row execute function internal.broadcast_notification_center_invalidation();
create policy teamzone_notification_center_broadcast_select on realtime.messages for select to authenticated using(
 realtime.messages.extension='broadcast'and(select realtime.topic())='notification:center:'||auth.uid()::text
);

create function internal.notification_deep_link(outbox internal.notification_outbox)
returns text language sql stable set search_path='' as $$
 select case
  when outbox.event_type='message.message.sent.v1'and outbox.payload_ref->>'thread_id'~'^[0-9a-fA-F-]{36}$'
   then '/inbox?thread='||outbox.payload_ref->>'thread_id'
  when outbox.event_type like 'callup.%'and outbox.payload_ref->>'event_id'~'^[0-9a-fA-F-]{36}$'
   then '/calendar?event='||outbox.payload_ref->>'event_id'
  when outbox.aggregate_type='event'then '/calendar?event='||outbox.aggregate_id::text
  else '/inbox'end
$$;

create function internal.notification_title(event_type text)
returns text language sql immutable set search_path='' as $$
 select case
  when event_type='message.message.sent.v1'then'Nytt meddelande'
  when event_type like 'callup.%.cancelled.%'then'Kallelse återkallad'
  when event_type like 'callup.%.reminded.%'then'Påminnelse om kallelse'
  when event_type like 'callup.%'then'Ny kallelse'
  when event_type like 'event.%'then'Kalendern har uppdaterats'
  else'Ny aktivitet i TeamZone'end
$$;

create function internal.notification_preview(event_type text)
returns text language sql immutable set search_path='' as $$
 select case
  when event_type='message.message.sent.v1'then'Öppna inkorgen för att läsa meddelandet.'
  when event_type like 'callup.%.cancelled.%'then'En kallelse har återkallats.'
  when event_type like 'callup.%.reminded.%'then'Du har en kallelse som behöver besvaras.'
  when event_type like 'callup.%'then'Du har fått en kallelse.'
  when event_type like 'event.%'then'Öppna kalendern för aktuell information.'
  else'Öppna TeamZone för mer information.'end
$$;

create function internal.list_notification_center_for_actor(page_before timestamptz default null,page_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 return jsonb_build_object('schema_version',2,'unread_count',(
  select count(*)from internal.notification_outbox outbox left join core.notification_receipts receipt
   on receipt.notification_id=outbox.id and receipt.profile_id=actor_id
  where outbox.recipient_profile_id=actor_id and receipt.notification_id is null
   and lower(outbox.event_type)not like'%watchpoint%'and lower(outbox.event_type)not like'%assistant%'
   and lower(outbox.event_type)not like'%assistant_coach%'and lower(outbox.event_type)not like'%ac_signal%'),
  'items',coalesce((select jsonb_agg(row_value order by created_at desc,id)from(
   select outbox.id,outbox.event_type,
    case when outbox.event_type='message.message.sent.v1'then'message'
     when outbox.event_type like'callup.%'then'callup'
     when outbox.event_type like'event.%'then'event'else'general'end category,
    internal.notification_title(outbox.event_type)title,internal.notification_preview(outbox.event_type)preview,
    internal.notification_deep_link(outbox)deep_link,receipt.notification_id is null unread,outbox.created_at
   from internal.notification_outbox outbox left join core.notification_receipts receipt
    on receipt.notification_id=outbox.id and receipt.profile_id=actor_id
   where outbox.recipient_profile_id=actor_id and coalesce(receipt.state,'read')<>'dismissed'
    and(page_before is null or outbox.created_at<page_before)
    and lower(outbox.event_type)not like'%watchpoint%'and lower(outbox.event_type)not like'%assistant%'
    and lower(outbox.event_type)not like'%assistant_coach%'and lower(outbox.event_type)not like'%ac_signal%'
   order by outbox.created_at desc,outbox.id limit greatest(1,least(page_limit,100)))row_value),'[]'::jsonb));
end$$;

create function internal.set_notification_state_for_actor(target_notification_id uuid,new_state text,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();existing jsonb;new_revision bigint;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='notification.state.set.v1'and internal.command_deduplication.idempotency_key=set_notification_state_for_actor.idempotency_key;
 if existing is not null then return(existing->>'revision')::bigint;end if;
 if new_state not in('read','dismissed')or not exists(select 1 from internal.notification_outbox
  where id=target_notification_id and recipient_profile_id=actor_id)
 then raise insufficient_privilege using message='not_found';end if;
 insert into core.notification_receipts(notification_id,profile_id,state)
 values(target_notification_id,actor_id,new_state)on conflict(notification_id,profile_id)do update
 set state=excluded.state,read_at=case when core.notification_receipts.state='read'then core.notification_receipts.read_at else now()end,
  updated_at=now(),revision=core.notification_receipts.revision+1 returning revision into new_revision;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'notification.state.set.v1',jsonb_build_object('revision',new_revision));
 return new_revision;
end$$;

create function internal.mark_all_notifications_read_for_actor(idempotency_key uuid)
returns integer language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();existing jsonb;affected integer;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='notification.read_all.v1'and internal.command_deduplication.idempotency_key=mark_all_notifications_read_for_actor.idempotency_key;
 if existing is not null then return(existing->>'affected')::integer;end if;
 insert into core.notification_receipts(notification_id,profile_id,state)
 select outbox.id,actor_id,'read'from internal.notification_outbox outbox
 where outbox.recipient_profile_id=actor_id and lower(outbox.event_type)not like'%watchpoint%'
  and lower(outbox.event_type)not like'%assistant%'and lower(outbox.event_type)not like'%assistant_coach%'
  and lower(outbox.event_type)not like'%ac_signal%'
 on conflict(notification_id,profile_id)do update set state=case when core.notification_receipts.state='dismissed'then'dismissed'else'read'end,
  updated_at=now(),revision=core.notification_receipts.revision+1;
 get diagnostics affected=row_count;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'notification.read_all.v1',jsonb_build_object('affected',affected));
 return affected;
end$$;

drop function if exists api.list_notification_center(integer);
create function api.list_notification_center(page_before timestamptz default null,page_limit integer default 50)
returns jsonb language sql stable security invoker set search_path=''as
$$select internal.list_notification_center_for_actor(page_before,page_limit)$$;
create function api.set_notification_state(notification_id uuid,state text,idempotency_key uuid)
returns bigint language sql security invoker set search_path=''as
$$select internal.set_notification_state_for_actor(notification_id,state,idempotency_key)$$;
create function api.mark_all_notifications_read(idempotency_key uuid)
returns integer language sql security invoker set search_path=''as
$$select internal.mark_all_notifications_read_for_actor(idempotency_key)$$;

revoke all on table core.notification_receipts from public,anon,authenticated;
revoke all on function internal.notification_deep_link(internal.notification_outbox),internal.notification_title(text),
 internal.notification_preview(text),internal.broadcast_notification_center_invalidation(),internal.list_notification_center_for_actor(timestamptz,integer),
 internal.set_notification_state_for_actor(uuid,text,uuid),internal.mark_all_notifications_read_for_actor(uuid),
 api.list_notification_center(timestamptz,integer),api.set_notification_state(uuid,text,uuid),api.mark_all_notifications_read(uuid)
 from public,anon,authenticated;
grant execute on function internal.list_notification_center_for_actor(timestamptz,integer),
 internal.set_notification_state_for_actor(uuid,text,uuid),internal.mark_all_notifications_read_for_actor(uuid),
 api.list_notification_center(timestamptz,integer),api.set_notification_state(uuid,text,uuid),api.mark_all_notifications_read(uuid)
 to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260827160606_msg08_notification_center','greenfield','MSG-08 safe notification center without Watchpoints or AC');
notify pgrst,'reload schema';
