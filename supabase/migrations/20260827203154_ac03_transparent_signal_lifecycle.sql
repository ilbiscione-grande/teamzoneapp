-- AC-03: transparent per-user signal lifecycle. No domain mutation and no AI.

create table internal.assistant_signal_receipts(
 profile_id uuid not null references core.profiles(id)on delete cascade,
 club_id uuid not null references core.clubs(id)on delete cascade,
 team_id uuid not null,
 signal_key text not null references internal.assistant_signal_registry(signal_key),
 source_id uuid not null,
 state text not null check(state in('visible','dismissed')),
 dismissed_at timestamptz,restored_at timestamptz,updated_at timestamptz not null default now(),
 revision bigint not null default 1 check(revision>0),
 primary key(profile_id,club_id,team_id,signal_key,source_id),
 foreign key(team_id,club_id)references core.teams(id,club_id)on delete cascade,
 check((state='dismissed'and dismissed_at is not null)or state='visible'),
 check(restored_at is null or dismissed_at is not null)
);
create index assistant_signal_receipts_history_idx
 on internal.assistant_signal_receipts(profile_id,club_id,team_id,state,updated_at desc);

create table audit.assistant_signal_receipt_events(
 id uuid primary key default gen_random_uuid(),profile_id uuid not null,
 club_id uuid not null,team_id uuid not null,signal_key text not null,source_id uuid not null,
 action text not null check(action in('dismissed','restored')),
 receipt_revision bigint not null check(receipt_revision>0),created_at timestamptz not null default now()
);

alter table internal.assistant_signal_receipts enable row level security;
alter table audit.assistant_signal_receipt_events enable row level security;
revoke all on table internal.assistant_signal_receipts,audit.assistant_signal_receipt_events from public,anon,authenticated;

create function internal.list_assistant_signals_for_actor(target_club_id uuid,target_team_id uuid,include_dismissed boolean default false)
returns jsonb language plpgsql stable security definer set search_path=''as $$
declare actor_id uuid:=auth.uid();gate_value jsonb;items jsonb;
begin
 if actor_id is null then raise insufficient_privilege using message='not_found';end if;
 gate_value:=internal.get_assistant_data_gate_for_actor(target_club_id,target_team_id);
 select coalesce(jsonb_agg(enriched order by enriched->>'signalKey',enriched->>'sourceId'),'[]'::jsonb)into items from(
  select signal||jsonb_build_object(
   'dismissed',coalesce(receipt.state='dismissed',false),
   'dismissedAt',receipt.dismissed_at,'receiptRevision',receipt.revision,
   'actionContract',jsonb_build_object(
    'kind','navigate','requiresExplicitUserAction',true,'performsDomainMutation',false))enriched
  from jsonb_array_elements(coalesce(gate_value->'signals','[]'::jsonb))signal
  left join internal.assistant_signal_receipts receipt on receipt.profile_id=actor_id
   and receipt.club_id=target_club_id and receipt.team_id=target_team_id
   and receipt.signal_key=signal->>'signalKey'and receipt.source_id=(signal->>'sourceId')::uuid
  where include_dismissed or coalesce(receipt.state,'visible')<>'dismissed'
 )rows;
 return jsonb_set(gate_value,'{signals}',items,true)||jsonb_build_object(
  'presentationContract',jsonb_build_object(
   'summaryKind','deterministic','riskScore',false,'medicalInference',false,
   'personComparison',false,'generativeAi',false,'domainMutation',false));
end$$;

create function internal.set_assistant_signal_state_for_actor(
 target_club_id uuid,target_team_id uuid,target_signal_key text,target_source_id uuid,
 new_state text,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path=''as $$
declare actor_id uuid:=auth.uid();gate_value jsonb;existing jsonb;new_revision bigint;command_name text;
begin
 if actor_id is null or idempotency_key is null or new_state not in('dismissed','visible')then
  raise insufficient_privilege using message='not_found';
 end if;
 command_name:=case when new_state='dismissed'then'assistant.signal.dismiss.v1'else'assistant.signal.restore.v1'end;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and internal.command_deduplication.idempotency_key=set_assistant_signal_state_for_actor.idempotency_key
  and command_type=command_name;
 if existing is not null then return(existing->>'revision')::bigint;end if;
 gate_value:=internal.get_assistant_data_gate_for_actor(target_club_id,target_team_id);
 if not exists(select 1 from jsonb_array_elements(coalesce(gate_value->'signals','[]'::jsonb))signal
  where signal->>'signalKey'=target_signal_key and signal->>'sourceId'=target_source_id::text
   and coalesce((signal->>'authorized')::boolean,false))then
  raise insufficient_privilege using message='not_found';
 end if;
 if new_state='visible'and not exists(select 1 from internal.assistant_signal_receipts receipt
  where receipt.profile_id=actor_id and receipt.club_id=target_club_id and receipt.team_id=target_team_id
   and receipt.signal_key=target_signal_key and receipt.source_id=target_source_id and receipt.state='dismissed')then
  raise insufficient_privilege using message='not_found';
 end if;
 insert into internal.assistant_signal_receipts(
  profile_id,club_id,team_id,signal_key,source_id,state,dismissed_at,restored_at)
 values(actor_id,target_club_id,target_team_id,target_signal_key,target_source_id,new_state,
  case when new_state='dismissed'then now()else null end,
  null)
 on conflict(profile_id,club_id,team_id,signal_key,source_id)do update set
  state=excluded.state,
  dismissed_at=case when excluded.state='dismissed'then now()else internal.assistant_signal_receipts.dismissed_at end,
  restored_at=case when excluded.state='visible'then now()else null end,
  updated_at=now(),revision=internal.assistant_signal_receipts.revision+1
 returning revision into new_revision;
 insert into audit.assistant_signal_receipt_events(
  profile_id,club_id,team_id,signal_key,source_id,action,receipt_revision)
 values(actor_id,target_club_id,target_team_id,target_signal_key,target_source_id,
  case when new_state='dismissed'then'dismissed'else'restored'end,new_revision);
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,command_name,jsonb_build_object('revision',new_revision));
 return new_revision;
end$$;

create function api.list_assistant_signals(target_club_id uuid,target_team_id uuid,include_dismissed boolean default false)
returns jsonb language sql stable security invoker set search_path=''as $$
 select internal.list_assistant_signals_for_actor(target_club_id,target_team_id,include_dismissed)
$$;
create function api.dismiss_assistant_signal(target_club_id uuid,target_team_id uuid,signal_key text,source_id uuid,idempotency_key uuid)
returns bigint language sql security invoker set search_path=''as $$
 select internal.set_assistant_signal_state_for_actor(target_club_id,target_team_id,signal_key,source_id,'dismissed',idempotency_key)
$$;
create function api.restore_assistant_signal(target_club_id uuid,target_team_id uuid,signal_key text,source_id uuid,idempotency_key uuid)
returns bigint language sql security invoker set search_path=''as $$
 select internal.set_assistant_signal_state_for_actor(target_club_id,target_team_id,signal_key,source_id,'visible',idempotency_key)
$$;

revoke all on function internal.list_assistant_signals_for_actor(uuid,uuid,boolean),
 internal.set_assistant_signal_state_for_actor(uuid,uuid,text,uuid,text,uuid),
 api.list_assistant_signals(uuid,uuid,boolean),api.dismiss_assistant_signal(uuid,uuid,text,uuid,uuid),
 api.restore_assistant_signal(uuid,uuid,text,uuid,uuid)from public,anon,authenticated;
grant execute on function internal.list_assistant_signals_for_actor(uuid,uuid,boolean),
 internal.set_assistant_signal_state_for_actor(uuid,uuid,text,uuid,text,uuid),
 api.list_assistant_signals(uuid,uuid,boolean),api.dismiss_assistant_signal(uuid,uuid,text,uuid,uuid),
 api.restore_assistant_signal(uuid,uuid,text,uuid,uuid)to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260827203154_ac03_transparent_signal_lifecycle','greenfield','AC-03 deterministic summaries and independent dismiss/restore history; no notification mutation');
notify pgrst,'reload schema';
