-- AC-01: private, deterministic signal registry and data-gate diagnostics.
-- This migration does not activate Assistant Coach or generative processing.

create table internal.assistant_signal_registry(
 signal_key text primary key,
 label text not null,
 source_tables text[] not null check(cardinality(source_tables)>0),
 owner_capability text not null,
 freshness interval not null check(freshness>interval '0 seconds'),
 explanation_template text not null,
 safe_route_template text not null,
 lifecycle_state text not null default 'candidate' check(lifecycle_state in('candidate','verified','blocked')),
 sensitivity text not null default 'operational' check(sensitivity in('operational','personal','sensitive')),
 updated_at timestamptz not null default now(),revision bigint not null default 1 check(revision>0)
);

insert into internal.assistant_signal_registry
(signal_key,label,source_tables,owner_capability,freshness,explanation_template,safe_route_template)
values
 ('callup.unanswered','Obesvarade kallelser',array['core.events','core.callups'],'event.squad.manage',interval '15 minutes','Eventet har skickade kallelser som ännu inte har besvarats.','/calendar?event={event_id}'),
 ('event.near_without_participants','Nära event utan deltagarunderlag',array['core.events','core.squad_revisions','core.callups'],'event.squad.manage',interval '15 minutes','Eventet börjar inom 72 timmar men saknar aktiv deltagardraft eller skickade kallelser.','/calendar?event={event_id}'),
 ('event.missing_attendance','Avslutat event utan närvaro',array['core.events','core.callups','core.attendance_facts'],'event.attendance.manage',interval '15 minutes','Eventet är avslutat men accepterade deltagare saknar registrerad närvaro.','/calendar?event={event_id}'),
 ('event.responses_complete','Alla kallelser besvarade',array['core.events','core.callups'],'event.squad.manage',interval '15 minutes','Alla aktiva skickade kallelser för eventet har besvarats.','/calendar?event={event_id}'),
 ('calendar.future_gap','Framtida planeringslucka',array['core.events'],'event.manage',interval '60 minutes','Laget saknar ett planerat event under de kommande 14 dagarna.','/calendar');

alter table internal.assistant_signal_registry enable row level security;
revoke all on table internal.assistant_signal_registry from public,anon,authenticated;

create function internal.get_assistant_data_gate_for_actor(target_club_id uuid,target_team_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();gate_row internal.assistant_activation_gate%rowtype;
 can_squad boolean;can_attendance boolean;can_event boolean;can_development boolean;
 registry_value jsonb;signals_value jsonb:='[]'::jsonb;
begin
 if actor_id is null or target_club_id is null or target_team_id is null then
  raise insufficient_privilege using message='not_found';
 end if;
 can_squad:=internal.actor_has_capability(target_club_id,target_team_id,'event.squad.manage');
 can_attendance:=internal.actor_has_capability(target_club_id,target_team_id,'event.attendance.manage');
 can_event:=internal.actor_has_capability(target_club_id,target_team_id,'event.manage');
 can_development:=internal.actor_has_capability(target_club_id,target_team_id,'development.manage');
 if not(can_squad or can_attendance or can_event or can_development)then
  raise insufficient_privilege using message='not_found';
 end if;
 select * into gate_row from internal.assistant_activation_gate where gate_key='AC-01';
 select coalesce(jsonb_agg(jsonb_build_object(
  'signalKey',r.signal_key,'label',r.label,'sources',r.source_tables,
  'ownerCapability',r.owner_capability,'freshnessSeconds',extract(epoch from r.freshness)::bigint,
  'lifecycleState',r.lifecycle_state,'sensitivity',r.sensitivity,
  'authorized',case r.owner_capability when 'event.squad.manage' then can_squad
    when 'event.attendance.manage' then can_attendance when 'event.manage' then can_event else false end,
  'safeRouteTemplate',r.safe_route_template)order by r.signal_key),'[]'::jsonb)
 into registry_value from internal.assistant_signal_registry r;

 if can_squad then
  select signals_value||coalesce(jsonb_agg(item order by starts_at,event_id),'[]'::jsonb)into signals_value from(
   select e.starts_at,e.id event_id,jsonb_build_object(
    'signalKey','callup.unanswered','source','core.callups','sourceId',e.id,'observedAt',now(),
    'sourceUpdatedAt',max(coalesce(c.sent_at,c.created_at)),'freshUntil',now()+interval '15 minutes',
    'explanation',count(*)::text||' skickade kallelser väntar på svar.','safeAction','Öppna eventet',
    'route','/calendar?event='||e.id::text,'ownerCapability','event.squad.manage','authorized',true)item
   from core.events e join core.callups c on c.event_id=e.id and c.club_id=e.club_id
   where e.club_id=target_club_id and e.owning_team_id=target_team_id and e.state='scheduled'
    and e.starts_at>now()and c.state='pending'
   group by e.id,e.starts_at
  )q;

  select signals_value||coalesce(jsonb_agg(item order by starts_at,event_id),'[]'::jsonb)into signals_value from(
   select e.starts_at,e.id event_id,jsonb_build_object(
    'signalKey','event.near_without_participants','source','core.events/core.squad_revisions/core.callups',
    'sourceId',e.id,'observedAt',now(),'sourceUpdatedAt',e.updated_at,'freshUntil',now()+interval '15 minutes',
    'explanation','Eventet börjar inom 72 timmar och saknar deltagardraft eller skickade kallelser.',
    'safeAction','Planera deltagare','route','/calendar?event='||e.id::text,
    'ownerCapability','event.squad.manage','authorized',true)item
   from core.events e where e.club_id=target_club_id and e.owning_team_id=target_team_id and e.state='scheduled'
    and e.starts_at between now()and now()+interval '72 hours'
    and(not exists(select 1 from core.squad_revisions s where s.event_id=e.id and s.state in('draft','locked','sent'))
      or not exists(select 1 from core.callups c where c.event_id=e.id and c.state not in('draft','cancelled')))
  )q;

  select signals_value||coalesce(jsonb_agg(item order by starts_at,event_id),'[]'::jsonb)into signals_value from(
   select e.starts_at,e.id event_id,jsonb_build_object(
    'signalKey','event.responses_complete','source','core.callups','sourceId',e.id,'observedAt',now(),
    'sourceUpdatedAt',max(coalesce(c.sent_at,c.created_at)),'freshUntil',now()+interval '15 minutes',
    'explanation','Alla aktiva skickade kallelser har besvarats.','safeAction','Öppna eventet',
    'route','/calendar?event='||e.id::text,'ownerCapability','event.squad.manage','authorized',true)item
   from core.events e join core.callups c on c.event_id=e.id and c.club_id=e.club_id
   where e.club_id=target_club_id and e.owning_team_id=target_team_id and e.state='scheduled'
    and e.starts_at>now()and c.state in('pending','accepted','declined')
   group by e.id,e.starts_at having count(*)>0 and count(*)filter(where c.state='pending')=0
  )q;
 end if;

 if can_attendance then
  select signals_value||coalesce(jsonb_agg(item order by starts_at,event_id),'[]'::jsonb)into signals_value from(
   select e.starts_at,e.id event_id,jsonb_build_object(
    'signalKey','event.missing_attendance','source','core.events/core.callups/core.attendance_facts',
    'sourceId',e.id,'observedAt',now(),'sourceUpdatedAt',e.updated_at,'freshUntil',now()+interval '15 minutes',
    'explanation',count(*)::text||' accepterade deltagare saknar registrerad närvaro.',
    'safeAction','Registrera närvaro','route','/calendar?event='||e.id::text,
    'ownerCapability','event.attendance.manage','authorized',true)item
   from core.events e join core.callups c on c.event_id=e.id and c.club_id=e.club_id and c.state='accepted'
   left join core.attendance_facts a on a.event_id=e.id and a.club_person_id=c.club_person_id
   where e.club_id=target_club_id and e.owning_team_id=target_team_id
    and(e.state='completed'or e.ends_at<now())and e.ends_at>now()-interval '30 days'and a.id is null
   group by e.id,e.starts_at
  )q;
 end if;

 if can_event and not exists(select 1 from core.events e where e.club_id=target_club_id
   and e.owning_team_id=target_team_id and e.state='scheduled'and e.starts_at between now()and now()+interval '14 days')then
  signals_value:=signals_value||jsonb_build_array(jsonb_build_object(
   'signalKey','calendar.future_gap','source','core.events','sourceId',target_team_id,'observedAt',now(),
   'sourceUpdatedAt',null,'freshUntil',now()+interval '60 minutes',
   'explanation','Inget planerat event finns under de kommande 14 dagarna.','safeAction','Öppna kalendern',
   'route','/calendar','ownerCapability','event.manage','authorized',true));
 end if;

 return jsonb_build_object('gateKey',gate_row.gate_key,'state',gate_row.state,'reason',gate_row.reason,
  'generativeAiEnabled',false,'evaluatedAt',now(),'clubId',target_club_id,'teamId',target_team_id,
  'registry',registry_value,'signals',signals_value,
  'verification',jsonb_build_object('schema','implemented','runtime','pending','activationAllowed',false));
end$$;

create function api.get_assistant_data_gate(target_club_id uuid,target_team_id uuid)
returns jsonb language sql security invoker set search_path=''as $$
 select internal.get_assistant_data_gate_for_actor(target_club_id,target_team_id)
$$;
revoke all on function internal.get_assistant_data_gate_for_actor(uuid,uuid)from public,anon,authenticated;
revoke all on function api.get_assistant_data_gate(uuid,uuid)from public,anon,authenticated;
grant execute on function internal.get_assistant_data_gate_for_actor(uuid,uuid)to authenticated;
grant execute on function api.get_assistant_data_gate(uuid,uuid)to authenticated;

update internal.assistant_activation_gate set
 reason='AC-01-registret är implementerat lokalt; runtime-datakvalitet och freshness måste verifieras före aktivering.',
 updated_at=now(),revision=revision+1 where gate_key='AC-01';

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260827195852_ac01_data_gate_signal_registry','greenfield','AC-01 private deterministic registry; activation remains blocked pending runtime verification');
notify pgrst,'reload schema';
