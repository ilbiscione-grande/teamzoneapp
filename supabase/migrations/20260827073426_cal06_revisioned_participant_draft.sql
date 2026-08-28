alter table core.squad_revisions add column selection_source text not null default 'manual'
 check(selection_source in('manual','all','group','generator'));
alter table core.squad_revisions add column selection_context jsonb not null default '{}'::jsonb
 check(jsonb_typeof(selection_context)='object');
alter table core.squad_revisions add column dispatch_kind text not null default 'initial'
 check(dispatch_kind in('initial','late'));

create function internal.save_squad_draft_v2_for_actor(target_event_id uuid,member_ids uuid[],
 selection_source text,selection_context jsonb,expected_revision bigint,idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();event_row core.events%rowtype;current_row core.squad_revisions%rowtype;
 new_id uuid;new_revision bigint;existing jsonb;matched integer;group_key text;target_count integer;
 generated_ids uuid[];dispatch_value text;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='squad.draft.saved.v2'
  and internal.command_deduplication.idempotency_key=save_squad_draft_v2_for_actor.idempotency_key;
 if existing is not null then return existing;end if;
 select * into event_row from core.events where id=target_event_id for update;
 if event_row.id is null or event_row.archived_at is not null or not internal.actor_can_manage_squad(target_event_id)
 then raise insufficient_privilege using message='not_found';end if;
 if event_row.state not in('draft','scheduled') or member_ids is null
  or cardinality(member_ids) not between 1 and 100
  or selection_source not in('manual','all','group','generator')
  or selection_context is null or jsonb_typeof(selection_context)<>'object'
  or(select count(distinct value) from unnest(member_ids)value)<>cardinality(member_ids)
 then raise invalid_parameter_value using message='invalid_input';end if;
 perform pg_advisory_xact_lock(hashtextextended('event-squad:'||target_event_id::text,0));
 select * into current_row from core.squad_revisions where event_id=target_event_id
  and state in('draft','locked') order by revision desc limit 1 for update;
 if current_row.id is not null and(current_row.state<>'draft' or expected_revision is distinct from current_row.revision)
 then raise serialization_failure using message='stale_revision';end if;
 if current_row.id is null and expected_revision is not null
 then raise serialization_failure using message='stale_revision';end if;
 select count(*) into matched from unnest(member_ids)person_id
  where internal.person_eligibility_at_event(target_event_id,person_id) is not null;
 if matched<>cardinality(member_ids) then raise check_violation using message='member_not_eligible';end if;
 if selection_source='all' then
  if cardinality(member_ids)<>(select count(*) from core.club_people person where person.club_id=event_row.club_id
   and person.status='active' and internal.person_eligibility_at_event(target_event_id,person.id) is not null)
  then raise check_violation using message='selection_mismatch';end if;
 elsif selection_source='group' then
  group_key:=selection_context->>'eligibility_kind';
  if group_key not in('team_assignment','development','dispensation','loan','guest','cross_team')
   or exists(select 1 from unnest(member_ids)person_id
    where internal.person_eligibility_at_event(target_event_id,person_id)->>'kind'<>group_key)
   or cardinality(member_ids)<>(select count(*) from core.club_people person
    where person.club_id=event_row.club_id and person.status='active'
     and internal.person_eligibility_at_event(target_event_id,person.id)->>'kind'=group_key)
  then raise check_violation using message='selection_mismatch';end if;
 elsif selection_source='generator' then
  begin target_count:=(selection_context->>'target_count')::integer;
  exception when others then raise invalid_parameter_value using message='invalid_generator';end;
  if selection_context->>'generator'<>'balanced_v1' or target_count not between 1 and 100
   or target_count<>cardinality(member_ids)
  then raise invalid_parameter_value using message='invalid_generator';end if;
  select array_agg(candidate.id order by candidate.priority,candidate.name,candidate.id) into generated_ids
  from(select person.id,person.display_name name,
    case when internal.person_eligibility_at_event(target_event_id,person.id)->>'kind'='team_assignment' then 0 else 1 end priority
   from core.club_people person where person.club_id=event_row.club_id and person.status='active'
    and internal.person_eligibility_at_event(target_event_id,person.id) is not null
   order by priority,person.display_name,person.id limit target_count)candidate;
  if member_ids is distinct from generated_ids then raise check_violation using message='selection_mismatch';end if;
 end if;
 new_revision:=coalesce((select max(revision)+1 from core.squad_revisions where event_id=target_event_id),1);
 dispatch_value:=case when exists(select 1 from core.callups where event_id=target_event_id) then 'late' else 'initial' end;
 if current_row.id is not null then update core.squad_revisions set state='superseded' where id=current_row.id;end if;
 insert into core.squad_revisions(club_id,event_id,revision,created_by,selection_source,selection_context,dispatch_kind)
 values(event_row.club_id,target_event_id,new_revision,actor_id,selection_source,selection_context,dispatch_value)
 returning id into new_id;
 insert into core.squad_members(club_id,event_id,squad_revision_id,club_person_id,eligibility_id,
  source,eligibility_snapshot,created_by)
 select event_row.club_id,target_event_id,new_id,person_id,
  case when eligibility->>'kind'='team_assignment' then null else(eligibility->>'id')::uuid end,
  selection_source,eligibility,actor_id from(select person_id,
   internal.person_eligibility_at_event(target_event_id,person_id)eligibility from unnest(member_ids)person_id)s;
 existing:=jsonb_build_object('squad_revision_id',new_id,'revision',new_revision,
  'member_count',cardinality(member_ids),'dispatch_kind',dispatch_value,'selection_source',selection_source);
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'squad.draft.saved.v2',existing);
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,
  aggregate_revision,metadata) values(event_row.club_id,actor_id,'squad.draft.saved.v2','squad',new_id,
   new_revision,jsonb_build_object('source',selection_source,'context',selection_context,
    'member_count',cardinality(member_ids),'dispatch_kind',dispatch_value));
 return existing;
end;$$;

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
 insert into internal.command_deduplication values(actor_id,idempotency_key,'squad.locked.v1',existing,now());
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
 insert into internal.command_deduplication values(actor_id,idempotency_key,'callup.callup.sent.v1',existing,now());
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,
  aggregate_revision,metadata) values(squad.club_id,actor_id,'callup.callup.sent.v1','squad',squad.id,
   squad.revision,jsonb_build_object('count',created_count,'dispatch_kind',squad.dispatch_kind));return existing;
end;$$;

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
  'callups',coalesce((select jsonb_agg(jsonb_build_object('callup_id',callup.id,'person_id',callup.club_person_id,
   'name',person.display_name,'state',callup.state,'revision',callup.revision,'expires_at',callup.expires_at,
   'delivery_state',coalesce(outbox.state,'pending'),'can_respond',exists(select 1 from core.person_account_links link
    where link.profile_id=auth.uid() and link.club_id=callup.club_id and link.club_person_id=callup.club_person_id
     and link.state='active'))order by person.display_name) from core.callups callup
   join core.club_people person on person.id=callup.club_person_id left join lateral(select state
    from internal.notification_outbox where aggregate_id=callup.id order by created_at desc limit 1)outbox on true
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

create function api.save_squad_draft_v2(target_event_id uuid,member_ids uuid[],selection_source text,
 selection_context jsonb,expected_revision bigint,idempotency_key uuid) returns jsonb
language sql security invoker set search_path=''
as $$select internal.save_squad_draft_v2_for_actor(target_event_id,member_ids,selection_source,
 selection_context,expected_revision,idempotency_key)$$;

revoke all on function internal.save_squad_draft_v2_for_actor(uuid,uuid[],text,jsonb,bigint,uuid),
 api.save_squad_draft_v2(uuid,uuid[],text,jsonb,bigint,uuid) from public,anon,authenticated;
grant execute on function internal.save_squad_draft_v2_for_actor(uuid,uuid[],text,jsonb,bigint,uuid),
 api.save_squad_draft_v2(uuid,uuid[],text,jsonb,bigint,uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260827073426_cal06_revisioned_participant_draft','greenfield','CAL-06 one revisioned participant draft with explicit late dispatch');
notify pgrst,'reload schema';
