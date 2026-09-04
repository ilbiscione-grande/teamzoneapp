alter table core.callups add column if not exists last_reminded_at timestamptz;
alter table core.callups add column if not exists reminder_count integer not null default 0 check(reminder_count>=0);
create index if not exists callups_reminder_due_idx on core.callups(last_reminded_at,event_id)
 where state='pending';

alter table core.callup_response_tokens add column allowed_responses text[] not null
 default array['accepted','declined','tentative']::text[]
 check(allowed_responses<@array['accepted','declined','tentative']::text[] and cardinality(allowed_responses)>0);
alter table core.callup_response_tokens add column recipient_person_id uuid;
update core.callup_response_tokens token set recipient_person_id=callup.club_person_id
from core.callups callup where callup.id=token.callup_id;
alter table core.callup_response_tokens alter column recipient_person_id set not null;
alter table core.callup_response_tokens add constraint callup_response_tokens_recipient_fkey
 foreign key(recipient_person_id,club_id) references core.club_people(id,club_id);
create index response_tokens_recipient_active_idx
 on core.callup_response_tokens(recipient_person_id,expires_at) where state='issued';

create or replace function internal.respond_callup_for_actor(target_callup_id uuid,new_response text,
 acting_as_person_id uuid,decline_reason_code text,decline_reason_text text,expected_revision bigint,
 idempotency_key uuid) returns bigint language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();callup core.callups%rowtype;actor_person uuid;new_revision bigint;existing jsonb;
 reason_code text:=nullif(btrim(decline_reason_code),'');reason_text text:=nullif(btrim(decline_reason_text),'');
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='callup.response.recorded.v2'
  and internal.command_deduplication.idempotency_key=respond_callup_for_actor.idempotency_key;
 if existing is not null then return(existing->>'revision')::bigint;end if;
 select * into callup from core.callups where id=target_callup_id for update;
 if callup.id is null then raise insufficient_privilege using message='not_found';end if;
 select link.club_person_id into actor_person from core.person_account_links link
  where link.profile_id=actor_id and link.club_id=callup.club_id and link.state='active' limit 1;
 if actor_person=callup.club_person_id then
  if acting_as_person_id is not null then raise insufficient_privilege using message='invalid_acting_as';end if;
 elsif acting_as_person_id=callup.club_person_id and exists(select 1 from core.guardian_relations relation
  where relation.club_id=callup.club_id and relation.guardian_person_id=actor_person
   and relation.child_person_id=callup.club_person_id and relation.state='active'
   and relation.starts_at<=now() and(relation.ends_at is null or relation.ends_at>now())) then null;
 else raise insufficient_privilege using message='not_found';end if;
 if callup.revision<>expected_revision then raise serialization_failure using message='stale_revision';end if;
 if callup.state not in('pending','accepted','declined') or callup.expires_at<=now()
  or new_response not in('accepted','declined','tentative')
 then raise invalid_parameter_value using message='invalid_state';end if;
 if new_response='declined' then
  if reason_code not in('illness','injury','unavailable','transport','other')
   or(reason_code='other' and(reason_text is null or length(reason_text) not between 2 and 500))
   or(reason_code<>'other' and reason_text is not null)
  then raise invalid_parameter_value using message='invalid_decline_reason';end if;
 elsif reason_code is not null or reason_text is not null then
  raise invalid_parameter_value using message='unexpected_decline_reason';
 end if;
 new_revision:=callup.revision+1;
 insert into core.callup_responses(club_id,callup_id,response,decline_reason_code,decline_reason_text,
  actor_profile_id,acting_as_person_id,revision) values(callup.club_id,callup.id,new_response,reason_code,
   reason_text,actor_id,acting_as_person_id,new_revision);
 update core.callups set state=case when new_response='tentative' then 'pending' else new_response end,
  revision=new_revision where id=callup.id;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'callup.response.recorded.v2',jsonb_build_object('revision',new_revision));
 insert into audit.command_events(club_id,actor_profile_id,acting_as_person_id,command_type,aggregate_type,
  aggregate_id,aggregate_revision,metadata) values(callup.club_id,actor_id,acting_as_person_id,
   'callup.response.recorded.v2','callup',callup.id,new_revision,jsonb_build_object('response',new_response,
    'decline_reason_code',reason_code));return new_revision;
end;$$;

create function internal.remind_callup_for_actor(target_callup_id uuid,expected_revision bigint,
 idempotency_key uuid) returns bigint language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();callup core.callups%rowtype;new_revision bigint;domain_id uuid:=gen_random_uuid();existing jsonb;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='callup.callup.reminded.v2'
  and internal.command_deduplication.idempotency_key=remind_callup_for_actor.idempotency_key;
 if existing is not null then return(existing->>'revision')::bigint;end if;
 select * into callup from core.callups where id=target_callup_id for update;
 if callup.id is null or not internal.actor_can_manage_squad(callup.event_id)
 then raise insufficient_privilege using message='not_found';end if;
 if callup.revision<>expected_revision then raise serialization_failure using message='stale_revision';end if;
 if callup.state<>'pending' or callup.expires_at<=now()
  or callup.last_reminded_at is not null and callup.last_reminded_at>now()-interval'6 hours'
 then raise check_violation using message='reminder_not_due';end if;
 new_revision:=callup.revision+1;
 update core.callups set last_reminded_at=now(),reminder_count=reminder_count+1,revision=new_revision
 where id=callup.id;
 insert into internal.domain_outbox(id,club_id,event_type,aggregate_type,aggregate_id,aggregate_revision,payload)
 values(domain_id,callup.club_id,'callup.callup.reminded.v2','callup',callup.id,new_revision,
  jsonb_build_object('reminder_count',callup.reminder_count+1));
 insert into internal.notification_outbox(club_id,domain_event_id,event_type,aggregate_type,aggregate_id,
  recipient_profile_id,recipient_person_id,payload_ref)
 select callup.club_id,domain_id,'callup.callup.reminded.v2','callup',callup.id,link.profile_id,
  callup.club_person_id,jsonb_build_object('callup_id',callup.id,'event_id',callup.event_id,
   'reminder_count',callup.reminder_count+1) from(select 1)x left join core.person_account_links link
   on link.club_id=callup.club_id and link.club_person_id=callup.club_person_id and link.state='active';
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'callup.callup.reminded.v2',jsonb_build_object('revision',new_revision));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,
  aggregate_revision,metadata) values(callup.club_id,actor_id,'callup.callup.reminded.v2','callup',callup.id,
   new_revision,jsonb_build_object('cooldown_hours',6,'reminder_count',callup.reminder_count+1));return new_revision;
end;$$;

create or replace function internal.cancel_or_remind_callup_for_actor(target_callup_id uuid,action text,
 expected_revision bigint,idempotency_key uuid) returns bigint language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();callup core.callups%rowtype;new_revision bigint;domain_id uuid:=gen_random_uuid();existing jsonb;
begin
 if action='remind' then return internal.remind_callup_for_actor(target_callup_id,expected_revision,idempotency_key);end if;
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 if action<>'cancel' then raise invalid_parameter_value using message='invalid_input';end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='callup.callup.cancelled.v2'
  and internal.command_deduplication.idempotency_key=cancel_or_remind_callup_for_actor.idempotency_key;
 if existing is not null then return(existing->>'revision')::bigint;end if;
 select * into callup from core.callups where id=target_callup_id for update;
 if callup.id is null or not internal.actor_can_manage_squad(callup.event_id)
 then raise insufficient_privilege using message='not_found';end if;
 if callup.revision<>expected_revision or callup.state='cancelled'
 then raise serialization_failure using message='stale_revision';end if;
 new_revision:=callup.revision+1;
 update core.callups set state='cancelled',cancelled_at=now(),revision=new_revision where id=callup.id;
 update core.callup_response_tokens set state='revoked' where callup_id=callup.id and state='issued';
 insert into internal.domain_outbox(id,club_id,event_type,aggregate_type,aggregate_id,aggregate_revision,payload)
 values(domain_id,callup.club_id,'callup.callup.cancelled.v2','callup',callup.id,new_revision,'{}');
 insert into internal.notification_outbox(club_id,domain_event_id,event_type,aggregate_type,aggregate_id,
  recipient_profile_id,recipient_person_id,payload_ref) select callup.club_id,domain_id,
  'callup.callup.cancelled.v2','callup',callup.id,link.profile_id,callup.club_person_id,
  jsonb_build_object('callup_id',callup.id,'event_id',callup.event_id) from(select 1)x
  left join core.person_account_links link on link.club_id=callup.club_id
   and link.club_person_id=callup.club_person_id and link.state='active';
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'callup.callup.cancelled.v2',jsonb_build_object('revision',new_revision));
 return new_revision;
end;$$;

create or replace function internal.issue_callup_response_token_for_actor(target_callup_id uuid,raw_token text,
 expiry timestamptz,idempotency_key uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();callup core.callups%rowtype;token_id uuid;existing jsonb;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='callup.push_action_token.issued.v2'
  and internal.command_deduplication.idempotency_key=issue_callup_response_token_for_actor.idempotency_key;
 if existing is not null then return(existing->>'token_id')::uuid;end if;
 select * into callup from core.callups where id=target_callup_id for update;
 if callup.id is null or callup.state<>'pending' or not internal.actor_can_manage_squad(callup.event_id)
 then raise insufficient_privilege using message='not_found';end if;
 if length(raw_token)<32 or expiry<=now() or expiry>least(callup.expires_at,now()+interval'15 minutes')
 then raise invalid_parameter_value using message='invalid_input';end if;
 update core.callup_response_tokens set state='revoked' where callup_id=callup.id and state='issued';
 insert into core.callup_response_tokens(club_id,callup_id,token_hash,expires_at,recipient_person_id)
 values(callup.club_id,callup.id,extensions.digest(raw_token,'sha256'),expiry,callup.club_person_id)
 returning id into token_id;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'callup.push_action_token.issued.v2',jsonb_build_object('token_id',token_id));
 return token_id;
end;$$;

create or replace function internal.respond_callup_with_token_for_actor(raw_token text,new_response text,
 acting_as_person_id uuid,decline_reason_code text,decline_reason_text text,expected_revision bigint,
 idempotency_key uuid) returns bigint language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();token_row core.callup_response_tokens%rowtype;result_revision bigint;existing jsonb;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='callup.response.recorded.v2'
  and internal.command_deduplication.idempotency_key=respond_callup_with_token_for_actor.idempotency_key;
 if existing is not null then return(existing->>'revision')::bigint;end if;
 select * into token_row from core.callup_response_tokens
  where token_hash=extensions.digest(raw_token,'sha256') for update;
 if token_row.id is null or token_row.state<>'issued' or token_row.expires_at<=now()
  or not(new_response=any(token_row.allowed_responses))
 then raise insufficient_privilege using message='invalid_or_expired_token';end if;
 result_revision:=internal.respond_callup_for_actor(token_row.callup_id,new_response,acting_as_person_id,
  decline_reason_code,decline_reason_text,expected_revision,idempotency_key);
 update core.callup_response_tokens set state='consumed',consumed_at=now() where id=token_row.id;
 return result_revision;
end;$$;

create or replace function internal.actor_callup_response_context(target_callup_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce((
  select case
   when exists(select 1 from core.person_account_links link where link.profile_id=auth.uid()
    and link.club_id=callup.club_id and link.club_person_id=callup.club_person_id and link.state='active')
   then jsonb_build_object('can_respond',true,'acting_as_person_id',null,'response_role','self')
   when exists(select 1 from core.person_account_links link join core.guardian_relations relation
    on relation.club_id=link.club_id and relation.guardian_person_id=link.club_person_id
    and relation.child_person_id=callup.club_person_id and relation.state='active'
    and relation.starts_at<=now() and(relation.ends_at is null or relation.ends_at>now())
    where link.profile_id=auth.uid() and link.club_id=callup.club_id and link.state='active')
   then jsonb_build_object('can_respond',true,'acting_as_person_id',callup.club_person_id,'response_role','guardian')
   else jsonb_build_object('can_respond',false,'acting_as_person_id',null,'response_role',null) end
  from core.callups callup where callup.id=target_callup_id),
  jsonb_build_object('can_respond',false,'acting_as_person_id',null,'response_role',null))
$$;

create or replace function internal.get_event_squad_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare event_row core.events%rowtype;squad core.squad_revisions%rowtype;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 select * into event_row from core.events where id=target_event_id;
 if event_row.id is null or not internal.actor_can_read_event(target_event_id)
 then raise insufficient_privilege using message='not_found';end if;
 select * into squad from core.squad_revisions where event_id=target_event_id order by revision desc limit 1;
 return jsonb_build_object('event_id',target_event_id,'squad_revision_id',squad.id,
  'squad_revision',squad.revision,'squad_state',coalesce(squad.state,'empty'),
  'selection_source',squad.selection_source,'selection_context',coalesce(squad.selection_context,'{}'::jsonb),
  'dispatch_kind',coalesce(squad.dispatch_kind,'initial'),
  'members',coalesce((select jsonb_agg(jsonb_build_object('person_id',member.club_person_id,
   'name',person.display_name,'selection_state',member.selection_state,'source',member.source)order by person.display_name)
   from core.squad_members member join core.club_people person on person.id=member.club_person_id
   where member.squad_revision_id=squad.id),'[]'::jsonb),
  'callups',coalesce((select jsonb_agg(jsonb_build_object('callup_id',callup.id,
   'person_id',callup.club_person_id,'name',person.display_name,'state',callup.state,
   'revision',callup.revision,'expires_at',callup.expires_at,'delivery_state',coalesce(sent.state,'pending'),
   'last_reminded_at',callup.last_reminded_at,'reminder_count',callup.reminder_count,
   'reminder_delivery_state',reminder.state,'can_respond',(response_context->>'can_respond')::boolean,
   'acting_as_person_id',response_context->>'acting_as_person_id','response_role',response_context->>'response_role')
   order by person.display_name) from core.callups callup join core.club_people person on person.id=callup.club_person_id
   cross join lateral internal.actor_callup_response_context(callup.id)response(response_context)
   left join lateral(select state from internal.notification_outbox where aggregate_id=callup.id
    and event_type in('callup.callup.sent.v1','callup.callup.late_sent.v1') order by created_at desc limit 1)sent on true
   left join lateral(select state from internal.notification_outbox where aggregate_id=callup.id
    and event_type='callup.callup.reminded.v2' order by created_at desc limit 1)reminder on true
   where callup.event_id=target_event_id),'[]'::jsonb),
  'attendance',coalesce((select jsonb_agg(jsonb_build_object('person_id',callup.club_person_id,
   'name',person.display_name,'status',coalesce(attendance.status,'unknown'),'minutes',attendance.minutes,
   'revision',coalesce(attendance.revision,0))order by person.display_name) from core.callups callup
   join core.club_people person on person.id=callup.club_person_id left join core.attendance_facts attendance
    on attendance.event_id=callup.event_id and attendance.club_person_id=callup.club_person_id
   where callup.event_id=target_event_id and callup.state<>'cancelled'),'[]'::jsonb),
  'caller_actions',case when internal.actor_can_manage_squad(target_event_id)
   then array['save_squad','lock_squad','send_callups','cancel_callup','remind_callup']::text[]
   else array[]::text[] end||case when internal.actor_can_manage_attendance(target_event_id)
   then array['record_attendance']::text[] else array[]::text[] end);
end;$$;

create function api.remind_callup(target_callup_id uuid,expected_revision bigint,idempotency_key uuid)
returns bigint language sql security invoker set search_path=''
as $$select internal.remind_callup_for_actor(target_callup_id,expected_revision,idempotency_key)$$;

revoke all on function internal.remind_callup_for_actor(uuid,bigint,uuid),
 internal.actor_callup_response_context(uuid),
 api.remind_callup(uuid,bigint,uuid) from public,anon,authenticated;
grant execute on function internal.remind_callup_for_actor(uuid,bigint,uuid),
 api.remind_callup(uuid,bigint,uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260827074757_cal07_callup_response_guardian_reminder_tokens','greenfield','CAL-07 guardian-aware responses, reminder cooldown and scoped push action tokens');
notify pgrst,'reload schema';
