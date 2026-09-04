-- Use explicit command_deduplication columns. The previous positional inserts
-- treated actor_profile_id as the table primary key and command_type as the
-- UUID idempotency key, causing lock/send to fail at runtime.

create or replace function internal.lock_squad_for_actor(target_event_id uuid,expected_revision bigint,
 idempotency_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();squad core.squad_revisions%rowtype;existing jsonb;invalid_count integer;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='squad.locked.v1' and internal.command_deduplication.idempotency_key=lock_squad_for_actor.idempotency_key;
 if existing is not null then return existing;end if;
 if not internal.actor_can_manage_squad(target_event_id) then raise insufficient_privilege using message='not_found';end if;
 perform pg_advisory_xact_lock(hashtextextended('event-squad:'||target_event_id::text,0));
 select * into squad from core.squad_revisions where event_id=target_event_id and state='draft' for update;
 if squad.id is null or squad.revision<>expected_revision then raise serialization_failure using message='stale_revision';end if;
 select count(*) into invalid_count from core.squad_members member where member.squad_revision_id=squad.id
  and internal.person_eligibility_at_event(target_event_id,member.club_person_id) is null;
 if invalid_count>0 then raise check_violation using message='member_not_eligible';end if;
 update core.squad_revisions set state='locked',locked_at=now(),eligibility_version=now() where id=squad.id;
 existing:=jsonb_build_object('squad_revision_id',squad.id,'revision',squad.revision,'state','locked',
  'dispatch_kind',squad.dispatch_kind);
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'squad.locked.v1',existing);
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision)
 values(squad.club_id,actor_id,'squad.locked.v1','squad',squad.id,squad.revision);return existing;
end;$$;

create or replace function internal.send_callups_for_actor(target_squad_revision_id uuid,expiry timestamptz,
 idempotency_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();squad core.squad_revisions%rowtype;existing jsonb;created_count integer;
 domain_id uuid:=gen_random_uuid();
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='callup.callup.sent.v1'
  and internal.command_deduplication.idempotency_key=send_callups_for_actor.idempotency_key;
 if existing is not null then return existing;end if;
 select * into squad from core.squad_revisions where id=target_squad_revision_id for update;
 if squad.id is null or not internal.actor_can_manage_squad(squad.event_id)
 then raise insufficient_privilege using message='not_found';end if;
 perform pg_advisory_xact_lock(hashtextextended('event-squad:'||squad.event_id::text,0));
 if squad.state<>'locked' or expiry<=now() then raise invalid_parameter_value using message='invalid_state';end if;
 if exists(select 1 from core.squad_members member where member.squad_revision_id=squad.id
  and internal.person_eligibility_at_event(squad.event_id,member.club_person_id) is null)
 then raise check_violation using message='member_not_eligible';end if;
 insert into core.callups(club_id,event_id,squad_revision_id,club_person_id,state,sent_at,expires_at,created_by)
 select squad.club_id,squad.event_id,squad.id,member.club_person_id,'pending',now(),expiry,actor_id
 from core.squad_members member where member.squad_revision_id=squad.id and member.selection_state='selected'
 on conflict do nothing;get diagnostics created_count=row_count;
 if squad.dispatch_kind='late' and created_count=0 then raise check_violation using message='no_new_recipients';end if;
 update core.squad_revisions set state='sent',sent_at=now() where id=squad.id;
 insert into internal.notification_outbox(id,club_id,domain_event_id,event_type,aggregate_type,aggregate_id,
  recipient_profile_id,recipient_person_id,payload_ref)
 select gen_random_uuid(),callup.club_id,domain_id,
  case when squad.dispatch_kind='late' then 'callup.callup.late_sent.v1' else 'callup.callup.sent.v1' end,
  'callup',callup.id,link.profile_id,callup.club_person_id,jsonb_build_object('callup_id',callup.id,
   'event_id',callup.event_id,'dispatch_kind',squad.dispatch_kind)
 from core.callups callup left join core.person_account_links link on link.club_id=callup.club_id
  and link.club_person_id=callup.club_person_id and link.state='active'
 where callup.squad_revision_id=squad.id on conflict do nothing;
 insert into internal.domain_outbox(id,club_id,event_type,aggregate_type,aggregate_id,aggregate_revision,payload)
 values(domain_id,squad.club_id,case when squad.dispatch_kind='late' then 'callup.callup.late_sent.v1'
  else 'callup.callup.sent.v1' end,'squad',squad.id,squad.revision,
  jsonb_build_object('count',created_count,'dispatch_kind',squad.dispatch_kind));
 existing:=jsonb_build_object('squad_revision_id',squad.id,'created_callups',created_count,'state','sent',
  'dispatch_kind',squad.dispatch_kind);
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'callup.callup.sent.v1',existing);
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,
  aggregate_revision,metadata) values(squad.club_id,actor_id,'callup.callup.sent.v1','squad',squad.id,
   squad.revision,jsonb_build_object('count',created_count,'dispatch_kind',squad.dispatch_kind));return existing;
end;$$;

revoke all on function internal.lock_squad_for_actor(uuid,bigint,uuid),
 internal.send_callups_for_actor(uuid,timestamptz,uuid) from public,anon,authenticated;
grant execute on function internal.lock_squad_for_actor(uuid,bigint,uuid),
 internal.send_callups_for_actor(uuid,timestamptz,uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260831202517_cal06_fix_command_deduplication_inserts','greenfield',
 'REL-02 runtime correction for explicit lock/send idempotency columns')
on conflict do nothing;

notify pgrst,'reload schema';
