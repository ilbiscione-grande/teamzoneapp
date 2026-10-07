-- Event KPIs and follow-up (step 1).
--
-- Leaders set KPI goals for an event in Förberedelser and follow them up in
-- Uppföljning. A KPI is picked from a built-in catalog (by event type and
-- sport) or is a custom team KPI. Its actual value is computed (attendance,
-- answers, late arrivals, match result) or entered after the event (manual).
-- Live counting in match mode comes in step 2 and can use the existing
-- match fact type 'kpi'.
--
-- Rights follow Förberedelser: goals for a training need training.plan, for
-- a match match.plan, otherwise event.logistics. Manual values can also be
-- entered by whoever registers attendance. Goals marked visible are shown to
-- players and guardians as team goals; everything else, and decline reasons,
-- stays with the event's leaders.

create or replace function internal.event_kpi_catalog()
returns jsonb language sql immutable set search_path='' as $$
 select '[
  {"key":"attendance_rate","label":"Närvaro","value_type":"percent","direction":"higher","source":"auto","event_types":["training","match","meeting","activity"],"sports":null},
  {"key":"response_rate","label":"Svar på kallelsen","value_type":"percent","direction":"higher","source":"auto","event_types":["training","match"],"sports":null},
  {"key":"late_count","label":"Sena ankomster","value_type":"count","direction":"lower","source":"auto","event_types":["training","match"],"sports":null},
  {"key":"goals_for","label":"Gjorda mål","value_type":"count","direction":"higher","source":"auto","event_types":["match"],"sports":null},
  {"key":"goals_against","label":"Insläppta mål","value_type":"count","direction":"lower","source":"auto","event_types":["match"],"sports":null},
  {"key":"clean_sheet","label":"Hålla nollan","value_type":"boolean","direction":"higher","source":"auto","event_types":["match"],"sports":["football"]},
  {"key":"shots","label":"Skott","value_type":"count","direction":"higher","source":"manual","event_types":["match"],"sports":null},
  {"key":"shots_on_target","label":"Skott på mål","value_type":"count","direction":"higher","source":"manual","event_types":["match"],"sports":null},
  {"key":"corners","label":"Hörnor","value_type":"count","direction":"higher","source":"manual","event_types":["match"],"sports":["football"]},
  {"key":"ball_wins_offensive","label":"Bollvinster på offensiv planhalva","value_type":"count","direction":"higher","source":"manual","event_types":["match"],"sports":["football"]},
  {"key":"save_rate","label":"Räddningsprocent","value_type":"percent","direction":"higher","source":"manual","event_types":["match"],"sports":["handball"]},
  {"key":"technical_faults","label":"Tekniska fel","value_type":"count","direction":"lower","source":"manual","event_types":["match"],"sports":["handball"]},
  {"key":"everyone_played_half","label":"Alla spelade minst halva matchen","value_type":"boolean","direction":"higher","source":"manual","event_types":["match"],"sports":null},
  {"key":"build_up_from_keeper","label":"Vågade spela ut från målvakten","value_type":"boolean","direction":"higher","source":"manual","event_types":["match"],"sports":["football"]},
  {"key":"focus_achieved","label":"Träningens fokus uppnått","value_type":"boolean","direction":"higher","source":"manual","event_types":["training"],"sports":null},
  {"key":"intensity","label":"Intensitet","value_type":"scale","direction":"higher","source":"manual","event_types":["training"],"sports":null}
 ]'::jsonb
$$;

create table core.event_kpi_targets(
 id uuid primary key default gen_random_uuid(),
 club_id uuid not null,
 event_id uuid not null,
 kpi_key text not null check(kpi_key ~ '^[a-z_]{2,40}$'),
 label text not null check(length(btrim(label)) between 1 and 80),
 value_type text not null check(value_type in('count','percent','boolean','scale','minutes')),
 direction text not null check(direction in('higher','lower')),
 source text not null check(source in('auto','manual')),
 comparator text not null check(comparator in('gte','lte','eq')),
 target numeric not null,
 visible_to_players boolean not null default false,
 position integer not null default 0,
 actual_value numeric,
 actual_recorded_at timestamptz,
 actual_recorded_by uuid references core.profiles(id),
 revision bigint not null default 1 check(revision>0),
 created_at timestamptz not null default now(),
 created_by uuid not null references core.profiles(id),
 updated_at timestamptz not null default now(),
 foreign key(event_id,club_id) references core.events(id,club_id) on delete cascade,
 check(source='manual' or actual_value is null),
 check(value_type<>'boolean' or (target in(0,1) and (actual_value is null or actual_value in(0,1)))),
 check(value_type<>'percent' or (target between 0 and 100 and (actual_value is null or actual_value between 0 and 100))),
 check(value_type<>'scale' or (target between 1 and 5 and (actual_value is null or actual_value between 1 and 5))),
 check(value_type not in('count','minutes') or (target>=0 and (actual_value is null or actual_value>=0)))
);
create unique index event_kpi_targets_label_idx on core.event_kpi_targets(event_id,lower(btrim(label)));
create index event_kpi_targets_event_idx on core.event_kpi_targets(event_id,position,created_at);
create index event_kpi_targets_trend_idx on core.event_kpi_targets(club_id,kpi_key,lower(btrim(label)));
alter table core.event_kpi_targets enable row level security;
create policy event_kpi_targets_no_direct_access on core.event_kpi_targets for all to authenticated using(false) with check(false);
revoke all on core.event_kpi_targets from public,anon,authenticated;

-- Who may set goals for this event type, and who may enter values.
create or replace function internal.actor_can_edit_event_kpis(target_event_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(
  select 1 from core.events e where e.id=target_event_id and e.archived_at is null and e.state<>'cancelled'
   and internal.actor_has_event_capability(e.id,
    case e.event_type when 'training' then 'training.plan' when 'match' then 'match.plan' else 'event.logistics' end))
$$;

create or replace function internal.actor_can_record_event_kpis(target_event_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select internal.actor_can_edit_event_kpis(target_event_id)
  or (auth.uid() is not null and exists(select 1 from core.events e where e.id=target_event_id and e.archived_at is null)
   and internal.actor_has_event_capability(target_event_id,'event.attendance.manage'))
$$;

-- Callups and attendance of one event. The attendance rate counts present,
-- late and partial against everyone called up, or against registered people
-- when there were no callups (walk-ins).
create or replace function internal.event_attendance_summary(target_event_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 with called as(
  select c.club_person_id,c.state from core.callups c where c.event_id=target_event_id and c.state<>'cancelled'
 ),facts as(
  select a.club_person_id,a.status,a.minutes from core.attendance_facts a where a.event_id=target_event_id
 ),counts as(
  select
   (select count(*) from called) called,
   (select count(*) from called where state='accepted') accepted,
   (select count(*) from called where state='declined') declined,
   (select count(*) from called where state='pending') pending,
   (select count(*) from facts where status='present') present,
   (select count(*) from facts where status='late') late,
   (select count(*) from facts where status='partial') partial,
   (select count(*) from facts where status='absent') absent,
   (select count(*) from facts where status<>'unknown') registered,
   (select round(avg(minutes)) from facts where status='late') late_minutes,
   (select count(*) from called c where not exists(select 1 from facts f where f.club_person_id=c.club_person_id and f.status<>'unknown')) unregistered
 )
 select jsonb_build_object('called',called,'accepted',accepted,'declined',declined,'pending',pending,
  'present',present,'late',late,'partial',partial,'absent',absent,'registered',registered,
  'unregistered',unregistered,'late_minutes_avg',late_minutes,
  'attendance_rate',case
   when registered=0 then null
   when called>0 then round(100.0*(present+late+partial)/called,1)
   else round(100.0*(present+late+partial)/registered,1) end,
  'response_rate',case when called=0 then null else round(100.0*(accepted+declined)/called,1) end)
 from counts
$$;

-- The actual value of a KPI for an event; null while unknown.
create or replace function internal.event_kpi_actual(target_event_id uuid,target_key text,target_source text,manual_value numeric)
returns numeric language plpgsql stable security definer set search_path='' as $$
declare summary jsonb; score record; ended boolean;
begin
 if target_source='manual' then return manual_value; end if;
 select e.ends_at<now() into ended from core.events e where e.id=target_event_id;
 if target_key in('attendance_rate','late_count','response_rate') then
  summary:=internal.event_attendance_summary(target_event_id);
  return case target_key
   when 'attendance_rate' then (summary->>'attendance_rate')::numeric
   when 'response_rate' then (summary->>'response_rate')::numeric
   when 'late_count' then case when coalesce(ended,false) and (summary->>'registered')::int>0
    then (summary->>'late')::numeric end
  end;
 end if;
 if target_key in('goals_for','goals_against','clean_sheet') then
  select p.score_us,p.score_opponent into score from core.match_projections p
  join core.match_workspaces w on w.event_id=p.event_id
  where p.event_id=target_event_id and w.state='completed';
  if score is null then return null; end if;
  return case target_key when 'goals_for' then score.score_us when 'goals_against' then score.score_opponent
   else case when score.score_opponent=0 then 1 else 0 end end;
 end if;
 return null;
end$$;

create or replace function internal.event_kpi_status(comparator text,target numeric,actual numeric,ended boolean)
returns text language sql immutable set search_path='' as $$
 select case
  when actual is null then case when ended then 'missing' else 'pending' end
  when comparator='gte' and actual>=target then 'achieved'
  when comparator='lte' and actual<=target then 'achieved'
  when comparator='eq' and actual=target then 'achieved'
  else 'missed' end
$$;

create or replace function internal.event_kpi_json(target core.event_kpi_targets,ended boolean,with_trend boolean)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',target.id,'kpi_key',target.kpi_key,'label',target.label,'value_type',target.value_type,
  'direction',target.direction,'source',target.source,'comparator',target.comparator,'target',target.target,
  'visible_to_players',target.visible_to_players,'position',target.position,'revision',target.revision,
  'actual',internal.event_kpi_actual(target.event_id,target.kpi_key,target.source,target.actual_value),
  'status',internal.event_kpi_status(target.comparator,target.target,
   internal.event_kpi_actual(target.event_id,target.kpi_key,target.source,target.actual_value),ended),
  -- The same KPI (key and label) on the team's previous events of this type.
  'trend',case when with_trend then coalesce((select jsonb_agg(point order by point->>'starts_at') from(
   select jsonb_build_object('event_id',e.id,'starts_at',e.starts_at,'target',t.target,
    'actual',internal.event_kpi_actual(e.id,t.kpi_key,t.source,t.actual_value),'current',e.id=target.event_id) point
   from core.event_kpi_targets t join core.events e on e.id=t.event_id
   join core.events current_event on current_event.id=target.event_id
   where t.club_id=target.club_id and t.kpi_key=target.kpi_key and lower(btrim(t.label))=lower(btrim(target.label))
    and e.owning_team_id=current_event.owning_team_id and e.event_type=current_event.event_type
    and e.archived_at is null and e.state<>'cancelled' and e.starts_at<=current_event.starts_at
   order by e.starts_at desc limit 6) recent),'[]'::jsonb) else '[]'::jsonb end)
$$;

create or replace function internal.get_event_kpi_catalog_for_actor(p_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare event_row core.events%rowtype; team_sport text;
begin
 select * into event_row from core.events where id=p_event_id;
 if auth.uid() is null or event_row.id is null or not internal.actor_can_read_event(p_event_id) then
  raise insufficient_privilege using message='not_found'; end if;
 select sport into team_sport from core.teams where id=event_row.owning_team_id;
 return coalesce((select jsonb_agg(item order by ordinality) from jsonb_array_elements(internal.event_kpi_catalog())
  with ordinality as catalog(item,ordinality)
  where item->'event_types' ? event_row.event_type
   and (item->'sports' is null or jsonb_typeof(item->'sports')='null' or item->'sports' ? team_sport)),'[]'::jsonb);
end$$;

create or replace function internal.save_event_kpi_target_for_actor(p_event_id uuid,p_target_id uuid,p_kpi_key text,
 p_label text,p_value_type text,p_comparator text,p_target numeric,p_visible boolean,p_expected_revision bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare event_row core.events%rowtype; entry jsonb; row_value core.event_kpi_targets%rowtype;
 clean_label text; kind text; direction_value text; source_value text; next_position integer;
begin
 select * into event_row from core.events where id=p_event_id;
 if event_row.id is null or not internal.actor_can_edit_event_kpis(p_event_id) then
  raise insufficient_privilege using message='not_found'; end if;
 perform pg_advisory_xact_lock(hashtextextended('event_kpis:'||p_event_id::text,0));
 if p_comparator not in('gte','lte','eq') or p_target is null then
  raise invalid_parameter_value using message='invalid_kpi'; end if;
 if p_kpi_key='custom' then
  clean_label:=btrim(coalesce(p_label,''));
  kind:=p_value_type;
  if length(clean_label) not between 1 and 80 or kind not in('count','percent','boolean','scale','minutes') then
   raise invalid_parameter_value using message='invalid_kpi'; end if;
  direction_value:=case when p_comparator='lte' then 'lower' else 'higher' end;
  source_value:='manual';
 else
  select item into entry from jsonb_array_elements(internal.get_event_kpi_catalog_for_actor(p_event_id)) item
  where item->>'key'=p_kpi_key;
  if entry is null then raise invalid_parameter_value using message='invalid_kpi'; end if;
  clean_label:=entry->>'label'; kind:=entry->>'value_type';
  direction_value:=entry->>'direction'; source_value:=entry->>'source';
 end if;
 if p_target_id is null then
  select coalesce(max(position),-1)+1 into next_position from core.event_kpi_targets where event_id=p_event_id;
  insert into core.event_kpi_targets(club_id,event_id,kpi_key,label,value_type,direction,source,comparator,target,
   visible_to_players,position,created_by)
  values(event_row.club_id,p_event_id,p_kpi_key,clean_label,kind,direction_value,source_value,p_comparator,p_target,
   coalesce(p_visible,false),next_position,auth.uid())
  returning * into row_value;
 else
  select * into row_value from core.event_kpi_targets where id=p_target_id and event_id=p_event_id for update;
  if row_value.id is null then raise insufficient_privilege using message='not_found'; end if;
  if row_value.revision<>p_expected_revision then raise serialization_failure using message='stale_revision'; end if;
  update core.event_kpi_targets set kpi_key=p_kpi_key,label=clean_label,value_type=kind,direction=direction_value,
   source=source_value,comparator=p_comparator,target=p_target,visible_to_players=coalesce(p_visible,false),
   actual_value=case when source_value='manual' and kind=row_value.value_type then actual_value end,
   revision=revision+1,updated_at=now()
  where id=row_value.id returning * into row_value;
 end if;
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(event_row.club_id,auth.uid(),'event.kpi.target_saved.v1','event',p_event_id,row_value.revision,
  jsonb_build_object('kpi_key',row_value.kpi_key,'target',row_value.target));
 return internal.event_kpi_json(row_value,event_row.ends_at<now(),false);
end$$;

create or replace function internal.delete_event_kpi_target_for_actor(p_event_id uuid,p_target_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare event_row core.events%rowtype;
begin
 select * into event_row from core.events where id=p_event_id;
 if event_row.id is null or not internal.actor_can_edit_event_kpis(p_event_id) then
  raise insufficient_privilege using message='not_found'; end if;
 delete from core.event_kpi_targets where id=p_target_id and event_id=p_event_id;
 if not found then raise insufficient_privilege using message='not_found'; end if;
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(event_row.club_id,auth.uid(),'event.kpi.target_deleted.v1','event',p_event_id,1,jsonb_build_object('target_id',p_target_id));
end$$;

create or replace function internal.record_event_kpi_value_for_actor(p_target_id uuid,p_value numeric,p_expected_revision bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare row_value core.event_kpi_targets%rowtype; event_row core.events%rowtype;
begin
 select * into row_value from core.event_kpi_targets where id=p_target_id for update;
 if row_value.id is null or not internal.actor_can_record_event_kpis(row_value.event_id) then
  raise insufficient_privilege using message='not_found'; end if;
 if row_value.source<>'manual' then raise invalid_parameter_value using message='kpi_is_automatic'; end if;
 if row_value.revision<>p_expected_revision then raise serialization_failure using message='stale_revision'; end if;
 select * into event_row from core.events where id=row_value.event_id;
 update core.event_kpi_targets set actual_value=p_value,actual_recorded_at=case when p_value is null then null else now() end,
  actual_recorded_by=case when p_value is null then null else auth.uid() end,revision=revision+1,updated_at=now()
 where id=row_value.id returning * into row_value;
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(row_value.club_id,auth.uid(),'event.kpi.value_recorded.v1','event',row_value.event_id,row_value.revision,
  jsonb_build_object('target_id',row_value.id,'value',p_value));
 return internal.event_kpi_json(row_value,event_row.ends_at<now(),false);
end$$;

-- Everything the follow-up tab shows. Non-leaders get the team summary and
-- the goals marked visible; to-dos and decline reasons are for leaders.
create or replace function internal.get_event_followup_for_actor(p_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare event_row core.events%rowtype; leader boolean; can_edit boolean; can_record boolean; ended boolean;
 summary jsonb; kpis jsonb; todos jsonb:='[]'::jsonb; missing_kpis integer; has_result boolean; has_report boolean;
 average numeric;
begin
 select * into event_row from core.events where id=p_event_id;
 if auth.uid() is null or event_row.id is null or not internal.actor_can_read_event(p_event_id) then
  raise insufficient_privilege using message='not_found'; end if;
 leader:=internal.actor_is_event_leader(p_event_id);
 can_edit:=internal.actor_can_edit_event_kpis(p_event_id);
 can_record:=internal.actor_can_record_event_kpis(p_event_id);
 ended:=event_row.ends_at<now();
 summary:=internal.event_attendance_summary(p_event_id);

 kpis:=coalesce((select jsonb_agg(internal.event_kpi_json(t,ended,true) order by t.position,t.created_at)
  from core.event_kpi_targets t where t.event_id=p_event_id and (leader or t.visible_to_players)),'[]'::jsonb);

 -- Team average attendance over the previous eight events of this type.
 select round(avg((internal.event_attendance_summary(e.id)->>'attendance_rate')::numeric),1) into average
 from (select e.id from core.events e where e.owning_team_id=event_row.owning_team_id and e.event_type=event_row.event_type
  and e.id<>event_row.id and e.archived_at is null and e.state<>'cancelled' and e.ends_at<now() and e.starts_at<event_row.starts_at
  order by e.starts_at desc limit 8) e;

 if leader and ended then
  if (summary->>'called')::int>0 and (summary->>'unregistered')::int>0 then
   todos:=todos||jsonb_build_object('kind','attendance','count',(summary->>'unregistered')::int);
  end if;
  select count(*) into missing_kpis from core.event_kpi_targets t where t.event_id=p_event_id and t.source='manual' and t.actual_value is null;
  if missing_kpis>0 then todos:=todos||jsonb_build_object('kind','kpi_values','count',missing_kpis); end if;
  if event_row.event_type='match' then
   select exists(select 1 from core.match_workspaces w where w.event_id=p_event_id and w.state='completed') into has_result;
   select exists(select 1 from core.match_reports r where r.event_id=p_event_id and length(btrim(coalesce(r.body,'')))>0) into has_report;
   if not has_result then todos:=todos||jsonb_build_object('kind','match_result','count',1); end if;
   if not has_report then todos:=todos||jsonb_build_object('kind','match_report','count',1); end if;
  end if;
 end if;

 return jsonb_build_object('event_id',p_event_id,'event_type',event_row.event_type,'ended',ended,
  'is_leader',leader,'can_edit_targets',can_edit,'can_record_values',can_record,
  'summary',summary,'team_average_attendance',average,
  'decline_reasons',case when leader then coalesce((select jsonb_agg(jsonb_build_object('code',code,'count',n) order by n desc,code)
   from(select coalesce(r.decline_reason_code,'other') code,count(*) n from core.callups c
    join lateral(select * from core.callup_responses r where r.callup_id=c.id order by r.revision desc limit 1) r on true
    where c.event_id=p_event_id and c.state='declined' group by 1) reasons),'[]'::jsonb) else '[]'::jsonb end,
  'attendance_trend',coalesce((select jsonb_agg(jsonb_build_object('event_id',id,'starts_at',starts_at,
    'attendance_rate',(internal.event_attendance_summary(id)->>'attendance_rate')::numeric,'current',id=p_event_id) order by starts_at)
   from(select e.id,e.starts_at from core.events e where e.owning_team_id=event_row.owning_team_id
    and e.event_type=event_row.event_type and e.archived_at is null and e.state<>'cancelled'
    and e.starts_at<=event_row.starts_at and (e.ends_at<now() or e.id=p_event_id)
    order by e.starts_at desc limit 6) recent),'[]'::jsonb),
  'kpis',kpis,'todos',todos);
end$$;

create or replace function api.get_event_kpi_catalog(p_event_id uuid) returns jsonb language sql stable security invoker set search_path='' as
$$select internal.get_event_kpi_catalog_for_actor(p_event_id)$$;
create or replace function api.save_event_kpi_target(p_event_id uuid,p_target_id uuid,p_kpi_key text,p_label text,p_value_type text,
 p_comparator text,p_target numeric,p_visible boolean,p_expected_revision bigint) returns jsonb language sql security invoker set search_path='' as
$$select internal.save_event_kpi_target_for_actor(p_event_id,p_target_id,p_kpi_key,p_label,p_value_type,p_comparator,p_target,p_visible,p_expected_revision)$$;
create or replace function api.delete_event_kpi_target(p_event_id uuid,p_target_id uuid) returns void language sql security invoker set search_path='' as
$$select internal.delete_event_kpi_target_for_actor(p_event_id,p_target_id)$$;
create or replace function api.record_event_kpi_value(p_target_id uuid,p_value numeric,p_expected_revision bigint) returns jsonb language sql security invoker set search_path='' as
$$select internal.record_event_kpi_value_for_actor(p_target_id,p_value,p_expected_revision)$$;
create or replace function api.get_event_followup(p_event_id uuid) returns jsonb language sql stable security invoker set search_path='' as
$$select internal.get_event_followup_for_actor(p_event_id)$$;

revoke all on function internal.event_kpi_catalog(),internal.actor_can_edit_event_kpis(uuid),internal.actor_can_record_event_kpis(uuid),
 internal.event_attendance_summary(uuid),internal.event_kpi_actual(uuid,text,text,numeric),internal.event_kpi_status(text,numeric,numeric,boolean),
 internal.event_kpi_json(core.event_kpi_targets,boolean,boolean),internal.get_event_kpi_catalog_for_actor(uuid),
 internal.save_event_kpi_target_for_actor(uuid,uuid,text,text,text,text,numeric,boolean,bigint),
 internal.delete_event_kpi_target_for_actor(uuid,uuid),internal.record_event_kpi_value_for_actor(uuid,numeric,bigint),
 internal.get_event_followup_for_actor(uuid),
 api.get_event_kpi_catalog(uuid),api.save_event_kpi_target(uuid,uuid,text,text,text,text,numeric,boolean,bigint),
 api.delete_event_kpi_target(uuid,uuid),api.record_event_kpi_value(uuid,numeric,bigint),api.get_event_followup(uuid)
 from public,anon,authenticated;
grant execute on function internal.event_kpi_catalog(),internal.actor_can_edit_event_kpis(uuid),internal.actor_can_record_event_kpis(uuid),
 internal.event_attendance_summary(uuid),internal.event_kpi_actual(uuid,text,text,numeric),internal.event_kpi_status(text,numeric,numeric,boolean),
 internal.event_kpi_json(core.event_kpi_targets,boolean,boolean),internal.get_event_kpi_catalog_for_actor(uuid),
 internal.save_event_kpi_target_for_actor(uuid,uuid,text,text,text,text,numeric,boolean,bigint),
 internal.delete_event_kpi_target_for_actor(uuid,uuid),internal.record_event_kpi_value_for_actor(uuid,numeric,bigint),
 internal.get_event_followup_for_actor(uuid),
 api.get_event_kpi_catalog(uuid),api.save_event_kpi_target(uuid,uuid,text,text,text,text,numeric,boolean,bigint),
 api.delete_event_kpi_target(uuid,uuid),api.record_event_kpi_value(uuid,numeric,bigint),api.get_event_followup(uuid)
 to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20261008090000_event_kpis_followup','greenfield','Event KPI goals in Förberedelser and the follow-up tab (step 1)');
notify pgrst,'reload schema';
