-- MSG-05 account-synced mute/pin, opt-in push and redacted message payloads.

create table core.thread_pins(
 thread_id uuid not null references core.message_threads(id) on delete cascade,
 profile_id uuid not null references core.profiles(id),
 pinned boolean not null default true,
 updated_at timestamptz not null default now(),
 revision bigint not null default 1 check(revision>0),
 primary key(thread_id,profile_id)
);
alter table core.thread_pins enable row level security;
create policy thread_pins_no_direct_access on core.thread_pins for all to authenticated using(false)with check(false);
create index thread_pins_profile_state_idx on core.thread_pins(profile_id,pinned,thread_id);
create trigger pins_inbox_invalidation after insert or update on core.thread_pins
for each row execute function internal.broadcast_inbox_invalidation();

create function internal.get_messaging_preferences_for_actor()
returns jsonb language sql stable security definer set search_path='' as $$
 select case when auth.uid() is null then jsonb_build_object('push_enabled',false,'pinned_thread_ids','[]'::jsonb)
 else jsonb_build_object(
  'push_enabled',coalesce((select preference.enabled from core.notification_preferences preference
   where preference.profile_id=auth.uid() and preference.event_type='message.message.sent.v1' and preference.channel='push'),false),
  'pinned_thread_ids',coalesce((select jsonb_agg(pin.thread_id order by pin.updated_at desc)from core.thread_pins pin
   where pin.profile_id=auth.uid() and pin.pinned and internal.actor_can_access_thread(pin.thread_id,false)),'[]'::jsonb)
 )end;
$$;

create function internal.set_messaging_push_for_actor(new_enabled boolean,idempotency_key uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();existing jsonb;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='message.push.preference.v1' and internal.command_deduplication.idempotency_key=set_messaging_push_for_actor.idempotency_key;
 if existing is not null then return(existing->>'enabled')::boolean;end if;
 insert into core.notification_preferences(profile_id,event_type,channel,enabled)
 values(actor_id,'message.message.sent.v1','push',new_enabled)
 on conflict(profile_id,event_type,channel)do update set enabled=excluded.enabled,updated_at=now();
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'message.push.preference.v1',jsonb_build_object('enabled',new_enabled));
 return new_enabled;
end;$$;

create function internal.set_thread_pin_for_actor(target_thread_id uuid,new_pinned boolean,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();existing jsonb;new_revision bigint;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='message.thread.pin.v1' and internal.command_deduplication.idempotency_key=set_thread_pin_for_actor.idempotency_key;
 if existing is not null then return(existing->>'revision')::bigint;end if;
 if not internal.actor_can_access_thread(target_thread_id,false)then raise insufficient_privilege using message='not_found';end if;
 insert into core.thread_pins(thread_id,profile_id,pinned)values(target_thread_id,actor_id,new_pinned)
 on conflict(thread_id,profile_id)do update set pinned=excluded.pinned,updated_at=now(),revision=core.thread_pins.revision+1
 returning revision into new_revision;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'message.thread.pin.v1',jsonb_build_object('revision',new_revision,'pinned',new_pinned));
 return new_revision;
end;$$;

create function internal.sanitize_messaging_notification_payload()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.event_type='message.message.sent.v1' then
  new.payload_ref:=jsonb_build_object(
   'thread_id',new.payload_ref->>'thread_id',
   'message_id',new.payload_ref->>'message_id',
   'preview_key','new_message'
  );
 end if;
 return new;
end;$$;
create trigger notification_outbox_sanitize_message before insert or update of payload_ref,event_type
on internal.notification_outbox for each row execute function internal.sanitize_messaging_notification_payload();
update internal.notification_outbox set payload_ref=payload_ref where event_type='message.message.sent.v1';

create or replace function internal.claim_notification_batch(batch_size integer default 25)
returns setof internal.notification_outbox language plpgsql security definer set search_path='' as $$
begin
 if current_user not in('postgres','service_role')then raise insufficient_privilege;end if;
 update internal.notification_outbox outbox set state='suppressed',last_error_code='preference_or_mute',updated_at=now()
 where outbox.event_type='message.message.sent.v1' and outbox.state in('pending','failed')and(
  outbox.recipient_profile_id is null
  or not exists(select 1 from core.notification_preferences preference where preference.profile_id=outbox.recipient_profile_id
   and preference.event_type='message.message.sent.v1' and preference.channel='push' and preference.enabled)
  or exists(select 1 from core.thread_mutes mute where mute.profile_id=outbox.recipient_profile_id and mute.state='muted'
   and(mute.muted_until is null or mute.muted_until>now())and outbox.payload_ref->>'thread_id'~'^[0-9a-fA-F-]{36}$'
   and mute.thread_id=(outbox.payload_ref->>'thread_id')::uuid)
 );
 return query with claimed as(select id from internal.notification_outbox where state in('pending','failed')
  and available_at<=now()and attempt_count<5 order by available_at,id for update skip locked limit greatest(1,least(batch_size,100)))
 update internal.notification_outbox outbox set state='processing',attempt_count=attempt_count+1,updated_at=now()
 from claimed where outbox.id=claimed.id returning outbox.*;
end;$$;

create or replace function internal.list_threads_for_actor(target_context_ids uuid[],page_before timestamptz default null,page_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 if target_context_ids is null or cardinality(target_context_ids)=0 or cardinality(target_context_ids)>50
 then raise invalid_parameter_value using message='invalid_context_selection';end if;
 if exists(select 1 from unnest(target_context_ids)requested where not exists(
  select 1 from internal.get_my_contexts_for_actor()context where context.context_id=requested))
 then raise insufficient_privilege using message='not_found';end if;
 return jsonb_build_object('schema_version',2,'generated_at',now(),'threads',coalesce((select jsonb_agg(row_value order by pinned desc,last_at desc,id)from(
  select thread.id,thread.thread_type,thread.subject,thread.state,thread.revision,
   coalesce(last_message.created_at,thread.created_at)last_at,last_message.body last_message_preview,last_message.sender_name,
   greatest(thread.revision-coalesce(case when thread.thread_type='announcement' then announcement_read.through_revision
    else message_read.through_revision end,1),0)unread_count,
   coalesce(mute.state='muted' and(mute.muted_until is null or mute.muted_until>now()),false)muted,
   coalesce(pin.pinned,false)pinned,
   (thread.thread_type<>'announcement' or participant.participant_role in('creator','moderator'))can_send
  from core.message_threads thread join core.thread_participants participant on participant.thread_id=thread.id
   and participant.profile_id=auth.uid()and participant.state='active'
  join core.thread_scopes scope on scope.thread_id=thread.id join internal.get_my_contexts_for_actor()context
   on context.context_id=any(target_context_ids)and context.club_id=scope.club_id and(context.team_id is null or context.team_id=scope.team_id)
  left join core.message_reads message_read on message_read.thread_id=thread.id and message_read.profile_id=auth.uid()
  left join core.announcement_reads announcement_read on announcement_read.thread_id=thread.id and announcement_read.profile_id=auth.uid()
  left join core.thread_mutes mute on mute.thread_id=thread.id and mute.profile_id=auth.uid()
  left join core.thread_pins pin on pin.thread_id=thread.id and pin.profile_id=auth.uid()
  left join lateral(select message.created_at,case when message.state='sent' then left(message.body,160)else null end body,
   profile.display_name sender_name from core.messages message join core.profiles profile on profile.id=message.sender_profile_id
   where message.thread_id=thread.id order by message.revision desc limit 1)last_message on true
  where internal.actor_can_access_thread(thread.id,false)and(page_before is null or coalesce(last_message.created_at,thread.created_at)<page_before)
  group by thread.id,last_message.created_at,last_message.body,last_message.sender_name,message_read.through_revision,
   announcement_read.through_revision,mute.state,mute.muted_until,pin.pinned,participant.participant_role
  order by pinned desc,last_at desc,thread.id limit greatest(1,least(page_limit,100)))row_value),'[]'::jsonb));
end;$$;

create function api.get_messaging_preferences()
returns jsonb language sql stable security invoker set search_path='' as
$$select internal.get_messaging_preferences_for_actor()$$;
create function api.set_messaging_push(enabled boolean,idempotency_key uuid)
returns boolean language sql security invoker set search_path='' as
$$select internal.set_messaging_push_for_actor(enabled,idempotency_key)$$;
create function api.set_thread_pin(thread_id uuid,pinned boolean,idempotency_key uuid)
returns bigint language sql security invoker set search_path='' as
$$select internal.set_thread_pin_for_actor(thread_id,pinned,idempotency_key)$$;

revoke all on table core.thread_pins from public,anon,authenticated;
revoke all on function internal.get_messaging_preferences_for_actor(),internal.set_messaging_push_for_actor(boolean,uuid),
 internal.set_thread_pin_for_actor(uuid,boolean,uuid),internal.sanitize_messaging_notification_payload(),
 api.get_messaging_preferences(),api.set_messaging_push(boolean,uuid),api.set_thread_pin(uuid,boolean,uuid)
 from public,anon,authenticated;
grant execute on function internal.get_messaging_preferences_for_actor(),internal.set_messaging_push_for_actor(boolean,uuid),
 internal.set_thread_pin_for_actor(uuid,boolean,uuid),api.get_messaging_preferences(),api.set_messaging_push(boolean,uuid),
 api.set_thread_pin(uuid,boolean,uuid)to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260827151434_msg05_notification_preferences_pin_redaction','greenfield','MSG-05 account-synced preferences, opt-in push and generic preview');
notify pgrst,'reload schema';
