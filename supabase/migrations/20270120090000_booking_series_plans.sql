-- Explicit opt-in future plans. Existing occurrences are never rebuilt.
create table internal.booking_series_plans(
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references core.booking_organizations(id) on delete cascade,
 series_id uuid references core.booking_series(id) on delete cascade, recurrence_id uuid references core.recurrence_rules(id) on delete cascade,
 anchor_booking_id uuid not null references core.booking_bookings(id) on delete cascade,
 event_template_id uuid references core.events(id), actor_id uuid not null references core.profiles(id),
 configuration jsonb not null, event_template jsonb, revision bigint not null default 1,
 state text not null check(state in('active','paused')), last_error text, last_run_at timestamptz,
 check((series_id is null)<>(recurrence_id is null)), unique(series_id),unique(recurrence_id)
);
create table internal.booking_series_slots(
 id uuid primary key default gen_random_uuid(),plan_id uuid not null references internal.booking_series_plans(id) on delete cascade,
 position integer not null,local_start timestamp not null,local_end timestamp not null,
 state text not null default 'queued' check(state in('queued','created','blocked','skipped')),
 reason text,event_id uuid,group_id uuid,unique(plan_id,position),check(local_end>local_start)
);
create index booking_series_slots_pending on internal.booking_series_slots(plan_id,local_start) where state='queued';
alter table internal.booking_series_plans enable row level security;
alter table internal.booking_series_slots enable row level security;
revoke all on internal.booking_series_plans,internal.booking_series_slots from public,anon,authenticated;

create function internal.booking_plan_anchor(target_booking_id uuid) returns core.booking_bookings
language plpgsql security definer set search_path='' as $$
declare b core.booking_bookings;e core.events;o uuid;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 select * into b from core.booking_bookings where id=target_booking_id;
 if b.id is null or (internal.booking_actor_role(b.organization_id) is null and internal.booking_actor_leads_team(b.organization_id,b.team_id) is not true)
 or (b.booked_by<>auth.uid() and internal.booking_actor_role(b.organization_id) is distinct from 'admin' and internal.booking_actor_leads_team(b.organization_id,b.team_id) is not true)
 or (b.team_id is not null and internal.booking_actor_can_book_team(b.organization_id,b.team_id) is not true) then raise insufficient_privilege using message='not_allowed';end if;
 if b.event_id is not null then
  select * into e from core.events where id=b.event_id;
  if e.recurrence_id is null or internal.actor_can_manage_event(e.id) is not true
   or internal.actor_has_capability(e.club_id,e.owning_team_id,'event.manage') is not true then raise insufficient_privilege using message='event_move_not_allowed';end if;
  perform pg_advisory_xact_lock(hashtextextended('event-series:'||e.recurrence_id::text,0));
  perform 1 from core.events where recurrence_id=e.recurrence_id order by occurrence_number,id for update;
  if exists(select 1 from core.booking_bookings x join core.events a on a.id=x.event_id where a.recurrence_id=e.recurrence_id and x.organization_id<>b.organization_id and x.status in('pending','confirmed')) then raise invalid_parameter_value using message='series_plan_multiple_organizations';end if;
 elsif b.series_id is not null then perform pg_advisory_xact_lock(hashtextextended('booking-series:'||b.series_id::text,0));
 else raise invalid_parameter_value using message='forward_series_not_found';end if;
 perform internal.lock_booking_organization(b.organization_id);
 select * into b from core.booking_bookings where id=target_booking_id for update;
 return b;
end;$$;
revoke all on function internal.booking_plan_anchor(uuid) from public,anon,authenticated;

create function internal.booking_plan_defaults(target_booking_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare b core.booking_bookings;e core.events;s core.booking_series;rule core.recurrence_rules;zone text;start_local timestamp;end_local timestamp;last_day date;next_day date;month_index int:=0;resources jsonb;
begin
 b:=internal.booking_plan_anchor(target_booking_id);
 if b.event_id is null then
  select * into s from core.booking_series where id=b.series_id;zone:=s.timezone;start_local:=b.starts_at at time zone zone;end_local:=b.ends_at at time zone zone;
  select greatest(s.ends_on,max((x.starts_at at time zone zone)::date)) into last_day from core.booking_bookings x where x.series_id=s.id;
 else
  select * into e from core.events where id=b.event_id;select * into rule from core.recurrence_rules where id=e.recurrence_id;
  zone:=e.timezone;start_local:=e.starts_at at time zone zone;end_local:=e.ends_at at time zone zone;
  select max((x.starts_at at time zone zone)::date) into last_day from core.events x where x.recurrence_id=e.recurrence_id;
 end if;
 -- Moving or cancelling an occurrence never makes its original logical slot
 -- available for a later template rebuild.
 select greatest(last_day,max(slot.local_start::date)) into last_day from internal.booking_series_plans p
 join internal.booking_series_slots slot on slot.plan_id=p.id where (p.series_id=b.series_id or p.recurrence_id=e.recurrence_id) and slot.state in('created','skipped');
 if exists(select 1 from (select x.resource_id,count(*) n from core.booking_bookings x where x.status in('pending','confirmed')
  and ((b.event_id is not null and x.event_id=b.event_id) or (b.event_id is null and x.id in(select id from internal.booking_resource_context(b)))) group by x.resource_id) q where q.n>1) then raise invalid_parameter_value using message='resource_series_ambiguous';end if;
 select coalesce(jsonb_agg(jsonb_build_object('resource_id',x.resource_id,'resource_name',r.name,
  'start_offset',extract(epoch from(x.starts_at-(start_local at time zone zone))),
  'end_offset',extract(epoch from(x.ends_at-(end_local at time zone zone)))) order by x.resource_id),'[]') into resources
 from core.booking_bookings x join core.booking_resources r on r.id=x.resource_id where x.status in('pending','confirmed') and
 ((b.event_id is not null and x.event_id=b.event_id) or (b.event_id is null and x.id in(select id from internal.booking_resource_context(b))));
 next_day:=last_day+1;
 if rule.frequency='daily' then next_day:=last_day+rule.interval_value;
 elsif rule.frequency='monthly' then
  loop next_day:=(rule.local_start::date+make_interval(months=>month_index*rule.interval_value))::date;exit when next_day>last_day;month_index:=month_index+1;if month_index>10000 then raise invalid_parameter_value using message='invalid_series';end if;end loop;
 end if;
 return jsonb_build_object('first_day',greatest(next_day,(now() at time zone zone)::date),'ends_on',greatest(next_day+28,(now() at time zone zone)::date+28),
  'start_time',start_local::time,'end_time',end_local::time,'end_day_offset',end_local::date-start_local::date,'timezone',zone,
  'frequency',coalesce(rule.frequency,'weekly'),'interval',coalesce(rule.interval_value,s.interval_weeks),
  'weekdays',coalesce(to_jsonb(s.weekdays),jsonb_build_array(extract(isodow from start_local)::int)),'resources',resources,
  'last_existing_day',last_day,'automatic',true);
end;$$;
revoke all on function internal.booking_plan_defaults(uuid) from public,anon,authenticated;

create function internal.booking_plan_slot_check(configuration jsonb,local_start timestamp,local_end timestamp,excluded_booking_ids uuid[] default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare ns timestamptz;ne timestamptz;rs timestamptz;re timestamptz;r core.booking_resources;v jsonb;claims jsonb:='[]';issues jsonb:='[]';zone text:=configuration->>'timezone';
begin
 ns:=local_start at time zone zone;ne:=local_end at time zone zone;
 if (ns at time zone zone)<>local_start or (ne at time zone zone)<>local_end or
 exists(select 1 from generate_series(-120,120,15) x where x<>0 and ((ns+x*interval '1 minute') at time zone zone=local_start or (ne+x*interval '1 minute') at time zone zone=local_end)) then issues:=issues||'[{"reason":"forward_invalid_local_time"}]'::jsonb;end if;
 for v in select value from jsonb_array_elements(configuration->'resources') loop
  select * into r from core.booking_resources where id=(v->>'resource_id')::uuid;
  rs:=ns+make_interval(secs=>(v->>'start_offset')::double precision);re:=ne+make_interval(secs=>(v->>'end_offset')::double precision);
  claims:=claims||jsonb_build_array(jsonb_build_object('resource_id',r.id,'resource_name',r.name,'starts_at',rs,'ends_at',re));
  if not r.active then issues:=issues||jsonb_build_array(jsonb_build_object('resource_name',r.name,'reason','resource_inactive'));
  elsif rs<=now() or re<=rs or re-rs>interval '31 days' then issues:=issues||jsonb_build_array(jsonb_build_object('resource_name',r.name,'reason','invalid_time'));
  elsif not internal.booking_within_disposition(r,rs,re) then issues:=issues||jsonb_build_array(jsonb_build_object('resource_name',r.name,'reason','resource_outside_disposition'));end if;
  if exists(select 1 from core.booking_bookings x where x.status in('pending','confirmed') and not(x.id=any(excluded_booking_ids)) and x.organization_id=r.organization_id and x.starts_at<re and x.ends_at>rs and internal.booking_resources_overlap(x.resource_id,r.id)) then
   issues:=issues||jsonb_build_array(jsonb_build_object('resource_name',r.name,'reason','resource_busy'));end if;
 end loop;
 if exists(select 1 from jsonb_array_elements(claims) a join jsonb_array_elements(claims) b on a->>'resource_id'<b->>'resource_id'
  where (a->>'starts_at')::timestamptz<(b->>'ends_at')::timestamptz and (a->>'ends_at')::timestamptz>(b->>'starts_at')::timestamptz
  and internal.booking_resources_overlap((a->>'resource_id')::uuid,(b->>'resource_id')::uuid)) then issues:=issues||'[{"reason":"resource_busy"}]'::jsonb;end if;
 return jsonb_build_object('starts_at',ns,'ends_at',ne,'bookings',claims,'conflicts',issues);
end;$$;
revoke all on function internal.booking_plan_slot_check(jsonb,timestamp,timestamp,uuid[]) from public,anon,authenticated;

create function internal.preview_booking_series_plan_for_actor(target_booking_id uuid,configuration jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare b core.booking_bookings;e core.events;prior internal.booking_series_plans;defaults jsonb;cfg jsonb:=configuration;resources jsonb:='[]';v jsonb;snapshot jsonb;
 firstday date;lastday date;d date;ls timestamp;le timestamp;freq text;step int;days smallint[];i int:=0;n int:=0;slots jsonb:='[]';slot jsonb;versions jsonb;
begin
 b:=internal.booking_plan_anchor(target_booking_id);defaults:=internal.booking_plan_defaults(target_booking_id);
 select * into e from core.events where id=b.event_id;
 select * into prior from internal.booking_series_plans p where p.series_id=b.series_id or p.recurrence_id=e.recurrence_id for update;
 if jsonb_typeof(cfg) is distinct from 'object' or jsonb_typeof(cfg->'resource_ids') is distinct from 'array' then raise invalid_parameter_value using message='invalid_series';end if;
 firstday:=(cfg->>'first_day')::date;lastday:=(cfg->>'ends_on')::date;freq:=cfg->>'frequency';step:=(cfg->>'interval')::int;
 days:=array(select value::smallint from jsonb_array_elements_text(cfg->'weekdays'));
 if firstday is null or lastday is null or firstday<=(defaults->>'last_existing_day')::date or firstday<(now() at time zone (cfg->>'timezone'))::date
 or lastday<firstday or lastday-firstday>366 or lastday>(now() at time zone (cfg->>'timezone'))::date+732
 or freq not in('daily','weekly','monthly') or step is null or step not between 1 and 52
 or cardinality(days) not between 1 and 7 or not(days<@array[1,2,3,4,5,6,7]::smallint[])
 or (cfg->>'end_day_offset')::int not between 0 and 31 or (cfg->>'end_day_offset') is null
 or not exists(select 1 from pg_timezone_names where name=cfg->>'timezone')
 or (cfg->>'start_time') is null or (cfg->>'end_time') is null or jsonb_typeof(cfg->'automatic') is distinct from 'boolean'
 or jsonb_array_length(cfg->'resource_ids')>10 or (b.event_id is null and jsonb_array_length(cfg->'resource_ids')=0) or (cfg->>'timezone') is distinct from (defaults->>'timezone') then raise invalid_parameter_value using message='invalid_series';end if;
 if (select count(distinct value) from jsonb_array_elements_text(cfg->'resource_ids'))<>jsonb_array_length(cfg->'resource_ids') then raise invalid_parameter_value using message='invalid_resource_set';end if;
 for v in select to_jsonb(r) from core.booking_resources r where r.id in(select value::uuid from jsonb_array_elements_text(cfg->'resource_ids')) and r.organization_id=b.organization_id order by r.id loop
  select q.value into snapshot from (select 1 priority_rank,value from jsonb_array_elements(defaults->'resources') union all select 2,value from jsonb_array_elements(prior.configuration->'resources')) q where q.value->>'resource_id'=v->>'id' order by q.priority_rank limit 1;
  resources:=resources||jsonb_build_array(jsonb_build_object('resource_id',v->'id','resource_name',v->'name',
   'start_offset',coalesce(snapshot->'start_offset','0'::jsonb),'end_offset',coalesce(snapshot->'end_offset','0'::jsonb)));
 end loop;
 if jsonb_array_length(resources)<>jsonb_array_length(cfg->'resource_ids') then raise insufficient_privilege using message='resource_change_not_found';end if;
 cfg:=jsonb_build_object('first_day',firstday,'ends_on',lastday,'frequency',freq,'interval',step,'weekdays',to_jsonb(array(select distinct x from unnest(days) x order by x)),
  'start_time',(cfg->>'start_time')::time,'end_time',(cfg->>'end_time')::time,'end_day_offset',(cfg->>'end_day_offset')::int,
  'timezone',cfg->>'timezone','resources',resources,'automatic',(cfg->>'automatic')::boolean);
 loop
  if freq='monthly' then d:=(firstday+make_interval(months=>i*step))::date;
  elsif freq='daily' then d:=firstday+i*step;
  else d:=firstday+i;end if;
  exit when d>lastday;i:=i+1;
  if freq='weekly' and (extract(isodow from d)::smallint<>all(days) or ((d-date_trunc('week',firstday)::date)/7)%step<>0) then continue;end if;
  ls:=d+(cfg->>'start_time')::time;le:=d+(cfg->>'end_day_offset')::int+(cfg->>'end_time')::time;
  if le<=ls or le-ls>interval '31 days' then raise invalid_parameter_value using message='invalid_time';end if;
  n:=n+1;if n>200 then raise invalid_parameter_value using message='series_too_long';end if;
  slot:=internal.booking_plan_slot_check(cfg,ls,le)||jsonb_build_object('local_start',ls,'local_end',le,'generate_now',d<=(now() at time zone (cfg->>'timezone'))::date+90);
  -- Compare to other new slots as well; buffers can cross occurrence boundaries.
  if exists(select 1 from jsonb_array_elements(slots) p cross join lateral jsonb_array_elements(p->'bookings') a cross join jsonb_array_elements(slot->'bookings') q
   where (a->>'starts_at')::timestamptz<(q->>'ends_at')::timestamptz and (a->>'ends_at')::timestamptz>(q->>'starts_at')::timestamptz
   and internal.booking_resources_overlap((a->>'resource_id')::uuid,(q->>'resource_id')::uuid)) then slot:=jsonb_set(slot,'{conflicts}',slot->'conflicts'||'[{"reason":"resource_busy"}]'::jsonb);end if;
  slots:=slots||jsonb_build_array(slot);
 end loop;
 if n=0 then raise invalid_parameter_value using message='invalid_series';end if;
 select jsonb_object_agg(r.id::text,r.revision) into versions from core.booking_resources r where r.id in(select a.id from jsonb_array_elements(resources) resource_item cross join lateral internal.booking_resource_ancestors((resource_item.value->>'resource_id')::uuid) a);
 return jsonb_build_object('target_booking_id',b.id,'plan_id',prior.id,'plan_revision',prior.revision,'configuration',cfg,'slots',slots,'resources',versions,
  'anchor',to_jsonb(b),'event',to_jsonb(e),'event_teams',(select jsonb_agg(to_jsonb(t) order by t.team_id) from core.event_teams t where t.event_id=e.id),
  'event_audiences',(select jsonb_agg(to_jsonb(a) order by a.audience_type,a.team_id) from core.event_audiences a where a.event_id=e.id),
  'previous_slots',(select coalesce(jsonb_agg(to_jsonb(x) order by x.position),'[]') from internal.booking_series_slots x where x.plan_id=prior.id));
end;$$;
revoke all on function internal.preview_booking_series_plan_for_actor(uuid,jsonb) from public,anon,authenticated;

create function api.preview_booking_series_plan(target_booking_id uuid,configuration jsonb) returns jsonb
language sql security definer set search_path='' as $$select internal.preview_booking_series_plan_for_actor(target_booking_id,configuration)$$;
revoke all on function api.preview_booking_series_plan(uuid,jsonb) from public,anon,authenticated;
grant execute on function api.preview_booking_series_plan(uuid,jsonb) to authenticated;

create function internal.create_booking_plan_event(p internal.booking_series_plans,slot internal.booking_series_slots,ns timestamptz,ne timestamptz) returns uuid
language plpgsql security definer set search_path='' as $$
declare seed core.events;eid uuid;n integer;v jsonb;fields jsonb;live_teams jsonb;live_audiences jsonb;
begin
 seed:=jsonb_populate_record(null::core.events,p.event_template->'event');
 select jsonb_agg(to_jsonb(t) order by t.team_id) into live_teams from core.event_teams t where t.event_id=p.event_template_id;
 select jsonb_agg(to_jsonb(a) order by a.audience_type,a.team_id) into live_audiences from core.event_audiences a where a.event_id=p.event_template_id;
 fields:=(to_jsonb(seed)-array['location_pitch','location_surface']);
 -- The standard event API remains responsible for capabilities, revisions,
 -- idempotency, event history and transactional domain events.
 fields:=jsonb_build_object('assembly_minutes_before',seed.assembly_minutes_before,'training_theme',seed.training_theme,
  'training_focus',seed.training_focus,'training_plan',seed.training_plan,'opponent_name',seed.opponent_name,
  'home_away',seed.home_away,'match_notes',seed.match_notes,'meeting_purpose',seed.meeting_purpose,'meeting_agenda',seed.meeting_agenda);
 eid:=internal.create_event_v2_for_actor(seed.club_id,seed.owning_team_id,seed.title,seed.description,seed.event_type,
  case when seed.state='draft' then 'draft' else 'scheduled' end,ns,ne,seed.all_day,p.configuration->>'timezone',
  array(select distinct audience_item.value->>'audience_type' from jsonb_array_elements(live_audiences) audience_item),null,null,null,null,fields,
  md5('booking-plan-event:'||slot.id::text)::uuid);
 select coalesce(max(occurrence_number),0)+1 into n from core.events where recurrence_id=p.recurrence_id;
 update core.events set recurrence_id=p.recurrence_id,occurrence_number=n,occurrence_key=n::text,
  location_id=seed.location_id,callups_required=seed.callups_required,referee_slots=seed.referee_slots,referee_kind=seed.referee_kind where id=eid;
 for v in select value from jsonb_array_elements(live_teams) where value->>'relation'<>'primary' loop
  insert into core.event_teams(club_id,event_id,team_id,relation,capabilities,created_by) values(seed.club_id,eid,(v->>'team_id')::uuid,v->>'relation',
   array(select jsonb_array_elements_text(v->'capabilities')),auth.uid());
 end loop;
 delete from core.event_audiences where event_id=eid;
 insert into core.event_audiences(club_id,event_id,audience_type,team_id,created_by)
 select seed.club_id,eid,audience_item.value->>'audience_type',(audience_item.value->>'team_id')::uuid,auth.uid() from jsonb_array_elements(live_audiences) audience_item;
 update core.event_revisions r set snapshot=internal.event_snapshot(e) from core.events e where e.id=eid and r.event_id=e.id and r.event_revision=1;
 update core.recurrence_rules set occurrence_count=greatest(coalesce(occurrence_count,0),n),revision=revision+1 where id=p.recurrence_id;
 update audit.command_events set metadata=metadata||jsonb_build_object('recurrence_id',p.recurrence_id,'series_plan_id',p.id,'slot_id',slot.id)
 where aggregate_id=eid and command_type='event.event.create.v1' and aggregate_revision=1;
 return eid;
end;$$;
revoke all on function internal.create_booking_plan_event(internal.booking_series_plans,internal.booking_series_slots,timestamptz,timestamptz) from public,anon,authenticated;

create function internal.generate_booking_series_plan_for_actor(target_plan_id uuid,through_date date default null,manual boolean default false) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p internal.booking_series_plans;b core.booking_bookings;s internal.booking_series_slots;check_result jsonb;v jsonb;row core.booking_bookings;
 eid uuid;gid uuid;seq integer;requested uuid;created int:=0;blocked int:=0;skipped int:=0;zone text;cutoff date;status text;
begin
 select * into p from internal.booking_series_plans where id=target_plan_id;
 if p.id is null then raise insufficient_privilege using message='not_found';end if;
 b:=internal.booking_plan_anchor(p.anchor_booking_id);
 select * into p from internal.booking_series_plans where id=target_plan_id for update;
 if p.state<>'active' and not manual then return jsonb_build_object('created',0,'blocked',0,'paused',true);end if;
 if auth.uid() is distinct from p.actor_id then raise sqlstate 'PT409' using message='stale_revision';end if;
 zone:=p.configuration->>'timezone';cutoff:=coalesce(through_date,(now() at time zone zone)::date)+90;
 for s in select * from internal.booking_series_slots where plan_id=p.id and state='queued' and local_start::date<=cutoff order by local_start,position for update loop
  if (s.local_start at time zone zone)<=now() then
   update internal.booking_series_slots set state='skipped',reason='past_occurrence' where id=s.id;skipped:=skipped+1;continue;end if;
  check_result:=internal.booking_plan_slot_check(p.configuration,s.local_start,s.local_end);
  if jsonb_array_length(check_result->'conflicts')>0 then
   update internal.booking_series_slots set state='blocked',reason=(check_result->'conflicts')::text where id=s.id;blocked:=blocked+1;continue;end if;
  begin
   eid:=null;gid:=gen_random_uuid();seq:=null;requested:=null;
   if p.recurrence_id is not null then eid:=internal.create_booking_plan_event(p,s,(check_result->>'starts_at')::timestamptz,(check_result->>'ends_at')::timestamptz);end if;
   for v in select value from jsonb_array_elements(check_result->'bookings') loop
    select case when r.requires_approval and internal.booking_actor_role(b.organization_id) is distinct from 'admin' then 'pending' else 'confirmed' end into status from core.booking_resources r where id=(v->>'resource_id')::uuid;
    insert into core.booking_bookings(organization_id,resource_id,starts_at,ends_at,title,notes,status,booked_by,team_id,event_id,group_id,series_id,series_sequence,decided_by,decided_at)
    values(b.organization_id,(v->>'resource_id')::uuid,(v->>'starts_at')::timestamptz,(v->>'ends_at')::timestamptz,
     b.title,b.notes,status,b.booked_by,b.team_id,eid,gid,p.series_id,seq,case when status='confirmed' then auth.uid() end,case when status='confirmed' then now() end) returning * into row;
    seq:=row.series_sequence;if status='pending' then requested:=row.id;end if;
   end loop;
   if requested is not null then perform internal.booking_notify(requested,'requested',array(select profile_id from internal.booking_admin_profiles(b.organization_id)));end if;
   update internal.booking_series_slots set state='created',reason=null,event_id=eid,group_id=gid where id=s.id;created:=created+1;
  exception when exclusion_violation or check_violation then
   -- An occurrence is atomic: an activity and every resource roll back together.
   update internal.booking_series_slots set state='blocked',reason=jsonb_build_array(jsonb_build_object('reason',case when sqlstate='23P01' then 'resource_busy' else 'generation_failed' end))::text where id=s.id;blocked:=blocked+1;
  end;
 end loop;
 update internal.booking_series_plans set last_run_at=now(),last_error=null,revision=revision+case when created+blocked+skipped>0 then 1 else 0 end where id=p.id;
 return jsonb_build_object('created',created,'blocked',blocked,'skipped',skipped);
end;$$;
revoke all on function internal.generate_booking_series_plan_for_actor(uuid,date,boolean) from public,anon,authenticated;

create function internal.save_booking_series_plan_for_actor(payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare plan jsonb;b core.booking_bookings;p internal.booking_series_plans;v jsonb;position integer;result jsonb;
begin
 if jsonb_typeof(payload->'expected_plan') is distinct from 'object' then raise invalid_parameter_value using message='revision_required';end if;
 plan:=internal.preview_booking_series_plan_for_actor((payload->>'target_booking_id')::uuid,payload->'configuration');
 if plan is distinct from payload->'expected_plan' then raise sqlstate 'PT409' using message='stale_revision';end if;
 select * into b from core.booking_bookings where id=(plan->>'target_booking_id')::uuid;
 select * into p from internal.booking_series_plans where id=(plan->>'plan_id')::uuid;
 if p.id is null then
  insert into internal.booking_series_plans(organization_id,series_id,recurrence_id,anchor_booking_id,event_template_id,actor_id,configuration,event_template,state)
  values(b.organization_id,b.series_id,(plan->'event'->>'recurrence_id')::uuid,b.id,b.event_id,auth.uid(),plan->'configuration',
   jsonb_build_object('event',plan->'event','teams',plan->'event_teams','audiences',plan->'event_audiences'),
   case when (plan->'configuration'->>'automatic')::boolean then 'active' else 'paused' end) returning * into p;
 else
  update internal.booking_series_plans set anchor_booking_id=b.id,event_template_id=b.event_id,actor_id=auth.uid(),configuration=plan->'configuration',
   event_template=jsonb_build_object('event',plan->'event','teams',plan->'event_teams','audiences',plan->'event_audiences'),
   state=case when (plan->'configuration'->>'automatic')::boolean then 'active' else 'paused' end,last_error=null,revision=revision+1 where id=p.id returning * into p;
 end if;
 -- Only virtual, never-created slots may be rebuilt. Created/skipped history is permanent.
 delete from internal.booking_series_slots where plan_id=p.id and state in('queued','blocked');
 select coalesce(max(s.position),0) into position from internal.booking_series_slots s where plan_id=p.id;
 for v in select value from jsonb_array_elements(plan->'slots') loop
  position:=position+1;insert into internal.booking_series_slots(plan_id,position,local_start,local_end) values(p.id,position,(v->>'local_start')::timestamp,(v->>'local_end')::timestamp);
 end loop;
 result:=internal.generate_booking_series_plan_for_actor(p.id);
 return jsonb_build_object('plan_id',p.id,'generation',result);
end;$$;
revoke all on function internal.save_booking_series_plan_for_actor(jsonb) from public,anon,authenticated;

create function internal.control_booking_series_plan_for_actor(payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p internal.booking_series_plans;action text:=payload->>'action';
begin
 select * into p from internal.booking_series_plans where id=(payload->>'plan_id')::uuid;
 if p.id is null then raise insufficient_privilege using message='not_found';end if;
 perform internal.booking_plan_anchor(p.anchor_booking_id);
 select * into p from internal.booking_series_plans where id=p.id for update;
 if (payload->>'expected_revision')::bigint is distinct from p.revision then raise sqlstate 'PT409' using message='stale_revision';end if;
 if action='pause' then update internal.booking_series_plans set state='paused',configuration=jsonb_set(configuration,'{automatic}','false'::jsonb),revision=revision+1 where id=p.id;
 elsif action='resume' then update internal.booking_series_plans set state='active',configuration=jsonb_set(configuration,'{automatic}','true'::jsonb),actor_id=auth.uid(),revision=revision+1 where id=p.id;return internal.generate_booking_series_plan_for_actor(p.id);
 elsif action='retry' then update internal.booking_series_plans set actor_id=auth.uid(),revision=revision+1 where id=p.id;update internal.booking_series_slots set state='queued',reason=null where plan_id=p.id and state='blocked';return internal.generate_booking_series_plan_for_actor(p.id,null,true);
 else raise invalid_parameter_value using message='invalid_command';end if;
 return jsonb_build_object('plan_id',p.id);
end;$$;
revoke all on function internal.control_booking_series_plan_for_actor(jsonb) from public,anon,authenticated;

create function internal.run_booking_series_plans() returns jsonb
language plpgsql security definer set search_path='' as $$
declare p internal.booking_series_plans;previous_actor text:=current_setting('request.jwt.claim.sub',true);n integer:=0;
begin
 if not pg_try_advisory_xact_lock(hashtextextended('booking-series-plans-worker',0)) then return '{"busy":true}'::jsonb;end if;
 -- One series per transaction avoids carrying one series' organization lock
 -- into the next series' advisory lock while an interactive edit is waiting.
 for p in select candidate.* from internal.booking_series_plans candidate where candidate.state='active' and exists(select 1 from internal.booking_series_slots s where s.plan_id=candidate.id and s.state='queued') order by candidate.last_run_at nulls first,candidate.id limit 1 loop
  begin
   perform set_config('request.jwt.claim.sub',p.actor_id::text,true);
   perform internal.generate_booking_series_plan_for_actor(p.id);n:=n+1;
  exception when serialization_failure or sqlstate 'PT409' then null; -- a new author/configuration won the lock; retry next run
  when others then
   update internal.booking_series_plans set state='paused',configuration=jsonb_set(configuration,'{automatic}','false'::jsonb),last_error=case when sqlstate='42501' then 'not_allowed' else 'generation_failed' end,last_run_at=now(),revision=revision+1 where id=p.id and actor_id=p.actor_id and revision=p.revision;
  end;
 end loop;
 perform set_config('request.jwt.claim.sub',coalesce(previous_actor,''),true);
 return jsonb_build_object('checked',n);
end;$$;
revoke all on function internal.run_booking_series_plans() from public,anon,authenticated;

create function api.get_booking_series_plan(target_booking_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare b core.booking_bookings;e core.events;p internal.booking_series_plans;cfg jsonb;
begin
 b:=internal.booking_plan_anchor(target_booking_id);select * into e from core.events where id=b.event_id;
 select * into p from internal.booking_series_plans where series_id=b.series_id or recurrence_id=e.recurrence_id;
 cfg:=coalesce(p.configuration,internal.booking_plan_defaults(b.id));
 return jsonb_build_object('plan',case when p.id is null then null else to_jsonb(p) end,'defaults',internal.booking_plan_defaults(b.id),
  'slots',(select coalesce(jsonb_agg(to_jsonb(s) order by s.position),'[]') from internal.booking_series_slots s where plan_id=p.id));
end;$$;
revoke all on function api.get_booking_series_plan(uuid) from public,anon,authenticated;
grant execute on function api.get_booking_series_plan(uuid) to authenticated;

create function api.list_booking_series_plans(target_organization_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb:='[]';p internal.booking_series_plans;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 for p in select * from internal.booking_series_plans where organization_id=target_organization_id order by id loop
  begin
   if not exists(select 1 from core.booking_bookings b left join core.events e on e.id=b.event_id where b.id=p.anchor_booking_id
    and (internal.booking_actor_role(b.organization_id) is not null or internal.booking_actor_leads_team(b.organization_id,b.team_id) is true)
    and (b.booked_by=auth.uid() or internal.booking_actor_role(b.organization_id)='admin' or internal.booking_actor_leads_team(b.organization_id,b.team_id) is true)
    and (b.team_id is null or internal.booking_actor_can_book_team(b.organization_id,b.team_id) is true)
    and (b.event_id is null or (internal.actor_can_manage_event(e.id) is true and internal.actor_has_capability(e.club_id,e.owning_team_id,'event.manage') is true))) then continue;end if;
   result:=result||jsonb_build_array(jsonb_build_object('id',p.id,'anchor_booking_id',p.anchor_booking_id,'revision',p.revision,'state',p.state,'last_error',p.last_error,
    'title',(select coalesce(title,'Bokningsserie') from core.booking_bookings where id=p.anchor_booking_id),'configuration',p.configuration,
    'slots',(select coalesce(jsonb_agg(to_jsonb(s) order by s.position),'[]') from internal.booking_series_slots s where plan_id=p.id)));
  exception when insufficient_privilege then null;end;
 end loop;return result;
end;$$;
revoke all on function api.list_booking_series_plans(uuid) from public,anon,authenticated;
grant execute on function api.list_booking_series_plans(uuid) to authenticated;

do $route$
declare definition text;marker text:='  case command_type';
begin
 definition:=pg_get_functiondef('internal.execute_booking_command_for_actor(uuid,text,jsonb,jsonb)'::regprocedure);
 if position(marker in definition)=0 then raise exception 'Command route missing';end if;
 execute replace(definition,marker,marker||E'\n    when ''save_booking_series_plan'' then result:=internal.save_booking_series_plan_for_actor(p);\n    when ''control_booking_series_plan'' then result:=internal.control_booking_series_plan_for_actor(p);');
end;$route$;

-- No existing series is opted in. The worker only processes explicitly saved plans.
do $cron$ begin
 if exists(select 1 from pg_extension where extname='pg_cron') then
  perform cron.schedule('booking-series-plans','* * * * *','select internal.run_booking_series_plans();');
 end if;
end;$cron$;

create function internal.booking_future_plan_projection(change jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare b core.booking_bookings;e core.events;p internal.booking_series_plans;cfg jsonb;source jsonb;v jsonb;q jsonb;
 resources jsonb:='[]';slots jsonb:='[]';conflicts jsonb:='[]';slot jsonb;row internal.booking_series_slots;
 ds interval;de interval;ls timestamp;le timestamp;zone text;excluded uuid[];versions jsonb;
begin
 if change->>'scope' not in('series_forward','series_all','event_forward','event_all') then return null;end if;
 select * into b from core.booking_bookings where id=(change->>'target_booking_id')::uuid;
 select * into e from core.events where id=b.event_id;
 select * into p from internal.booking_series_plans where series_id=b.series_id or recurrence_id=e.recurrence_id for update;
 if p.id is null then return null;end if;
 perform internal.booking_plan_anchor(p.anchor_booking_id);
 cfg:=p.configuration;zone:=change->'timing'->>'timezone';
 ds:=((change->>'new_starts_at')::timestamptz at time zone zone)-(coalesce(e.starts_at,b.starts_at) at time zone zone);
 de:=((change->>'new_ends_at')::timestamptz at time zone zone)-(coalesce(e.ends_at,b.ends_at) at time zone zone);
 select value into source from jsonb_array_elements(cfg->'resources') where value->>'resource_id'=change->'selection'->>'source_resource_id';
 for v in select value from jsonb_array_elements(cfg->'resources') loop
  if source is null or not(change->'remove_resource_ids' ? (v->>'resource_id')) then resources:=resources||jsonb_build_array(v);end if;
 end loop;
 if source is not null then
  for v in select value from jsonb_array_elements(change->'add_resource_ids') loop
   if not exists(select 1 from jsonb_array_elements(resources) r where r->'resource_id'=v) then
    resources:=resources||jsonb_build_array(source||jsonb_build_object('resource_id',v,'resource_name',(select name from core.booking_resources where id=(v#>>'{}')::uuid)));end if;
  end loop;
 end if;
 if jsonb_array_length(resources)>10 then raise invalid_parameter_value using message='too_many_resources';end if;
 ls:=(cfg->>'first_day')::date+(cfg->>'start_time')::time+ds;
 le:=(cfg->>'first_day')::date+(cfg->>'end_day_offset')::int+(cfg->>'end_time')::time+de;
 if le<=ls or le-ls>interval '31 days' then raise invalid_parameter_value using message='invalid_time';end if;
 cfg:=cfg||jsonb_build_object('resources',resources,'first_day',ls::date,'start_time',ls::time,'end_time',le::time,'end_day_offset',le::date-ls::date,
  'ends_on',(cfg->>'ends_on')::date+(ls::date-(cfg->>'first_day')::date),
  'weekdays',to_jsonb(array(select distinct (((x::int-1+ls::date-(cfg->>'first_day')::date)%7+7)%7+1) from jsonb_array_elements_text(cfg->'weekdays') x order by 1)));
 select coalesce(array_agg((booking_item.value->>'id')::uuid),'{}') into excluded from jsonb_array_elements(change->'timing'->'bookings') booking_item;
 for row in select * from internal.booking_series_slots where plan_id=p.id and state in('queued','blocked') order by position for update loop
  slot:=internal.booking_plan_slot_check(cfg,row.local_start+ds,row.local_end+de,excluded)||jsonb_build_object('id',row.id,'local_start',row.local_start+ds,'local_end',row.local_end+de);
  if exists(select 1 from jsonb_array_elements(slot->'bookings') a cross join jsonb_array_elements(change->'final_bookings') r where
   (a->>'starts_at')::timestamptz<(r->>'ends_at')::timestamptz and (a->>'ends_at')::timestamptz>(r->>'starts_at')::timestamptz and internal.booking_resources_overlap((a->>'resource_id')::uuid,(r->>'resource_id')::uuid))
   or exists(select 1 from jsonb_array_elements(slots) s cross join lateral jsonb_array_elements(s->'bookings') a cross join jsonb_array_elements(slot->'bookings') r where
   (a->>'starts_at')::timestamptz<(r->>'ends_at')::timestamptz and (a->>'ends_at')::timestamptz>(r->>'starts_at')::timestamptz and internal.booking_resources_overlap((a->>'resource_id')::uuid,(r->>'resource_id')::uuid)) then
   slot:=jsonb_set(slot,'{conflicts}',slot->'conflicts'||'[{"reason":"resource_busy"}]'::jsonb);end if;
  select conflicts||coalesce(jsonb_agg(conflict_item.value||jsonb_build_object('starts_at',slot->'starts_at','resource_name',coalesce(conflict_item.value->>'resource_name','Seriegrund'))),'[]') into conflicts from jsonb_array_elements(slot->'conflicts') conflict_item;
  slots:=slots||jsonb_build_array(slot);
 end loop;
 select jsonb_object_agg(r.id::text,r.revision) into versions from core.booking_resources r where r.id in(select a.id from jsonb_array_elements(resources) resource_item cross join lateral internal.booking_resource_ancestors((resource_item.value->>'resource_id')::uuid) a);
 return jsonb_build_object('id',p.id,'revision',p.revision,'state',case when p.series_id is not null and resources='[]'::jsonb then 'paused' else p.state end,
  'configuration',cfg,'slots',slots,'conflicts',conflicts,'resources',versions);
end;$$;
revoke all on function internal.booking_future_plan_projection(jsonb) from public,anon,authenticated;

-- Wrap the established preview so its exact reviewed snapshot also covers the
-- virtual future slots. The existing executor calls the same wrapper on save.
alter function internal.preview_booking_change_for_actor(uuid,text,timestamptz,timestamptz,uuid[],uuid[]) rename to preview_booking_change_without_future_for_actor;
create function internal.preview_booking_change_for_actor(target_booking_id uuid,change_scope text,new_starts_at timestamptz,new_ends_at timestamptz,add_resource_ids uuid[],remove_resource_ids uuid[]) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;future jsonb;
begin
 result:=internal.preview_booking_change_without_future_for_actor(target_booking_id,change_scope,new_starts_at,new_ends_at,add_resource_ids,remove_resource_ids);
 future:=internal.booking_future_plan_projection(result);
 return result||jsonb_build_object('future_plan',future,'conflicts',result->'conflicts'||coalesce(future->'conflicts','[]'::jsonb));
end;$$;
revoke all on function internal.preview_booking_change_for_actor(uuid,text,timestamptz,timestamptz,uuid[],uuid[]) from public,anon,authenticated;

create function internal.apply_booking_future_plan(change jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare f jsonb:=change->'future_plan';v jsonb;
begin
 if f is null or f='null'::jsonb then return;end if;
 update internal.booking_series_plans set configuration=jsonb_set(f->'configuration','{automatic}',to_jsonb(f->>'state'='active')),state=f->>'state',actor_id=auth.uid(),revision=revision+1,last_error=null
 where id=(f->>'id')::uuid and revision=(f->>'revision')::bigint;
 if not found then raise sqlstate 'PT409' using message='stale_revision';end if;
 for v in select value from jsonb_array_elements(f->'slots') loop
  update internal.booking_series_slots set local_start=(v->>'local_start')::timestamp,local_end=(v->>'local_end')::timestamp,state='queued',reason=null where id=(v->>'id')::uuid and plan_id=(f->>'id')::uuid;
 end loop;
 perform internal.generate_booking_series_plan_for_actor((f->>'id')::uuid);
end;$$;
revoke all on function internal.apply_booking_future_plan(jsonb) from public,anon,authenticated;

create function internal.guard_booking_series_plan_legacy(target_booking_id uuid,change_scope text) returns void
language plpgsql security definer set search_path='' as $$
declare b core.booking_bookings;e core.events;
begin
 if change_scope is null or change_scope not in('series_forward','series_all','event_forward','event_all') then return;end if;
 select * into b from core.booking_bookings where id=target_booking_id;
 if auth.uid() is null or (internal.booking_actor_role(b.organization_id) is null and internal.booking_actor_leads_team(b.organization_id,b.team_id) is not true) then return;end if;
 select * into e from core.events where id=b.event_id;
 if exists(select 1 from internal.booking_series_plans where series_id=b.series_id or recurrence_id=e.recurrence_id) then raise invalid_parameter_value using message='series_plan_requires_combined';end if;
end;$$;
revoke all on function internal.guard_booking_series_plan_legacy(uuid,text) from public,anon,authenticated;

do $hooks$
declare definition text;name text;sig text;marker text;
begin
 definition:=replace(pg_get_functiondef('internal.update_booking_for_actor(jsonb,uuid)'::regprocedure),E'\r\n',E'\n');
 marker:=' return plan;';if position(marker in definition)=0 then raise exception 'Combined save contract missing';end if;
 execute replace(definition,marker,' perform internal.apply_booking_future_plan(plan);'||E'\n'||marker);
 foreach sig in array array['api.preview_booking_time(uuid,text,timestamptz,timestamptz)','api.preview_booking_resource_series(uuid,uuid,text)','api.preview_booking_resources(uuid,text,uuid[],uuid[])'] loop
  definition:=replace(pg_get_functiondef(sig::regprocedure),E'\r\n',E'\n');marker:='begin';
  execute replace(definition,marker,marker||' perform internal.guard_booking_series_plan_legacy(target_booking_id,change_scope);');
 end loop;
 foreach sig in array array['internal.reschedule_booking_for_actor(jsonb,uuid)','internal.change_booking_resource_for_actor(jsonb)','internal.update_booking_resources_for_actor(jsonb)'] loop
  definition:=replace(pg_get_functiondef(sig::regprocedure),E'\r\n',E'\n');marker:=E'begin\n';
  if position(marker in definition)=0 then raise exception 'Legacy save contract missing: %',sig;end if;
  execute replace(definition,marker,marker||' perform internal.guard_booking_series_plan_legacy((p->>''target_booking_id'')::uuid,p->>''change_scope'');'||E'\n');
 end loop;
 definition:=replace(pg_get_functiondef('internal.revise_event_v2_for_actor(uuid,text,jsonb,bigint,uuid)'::regprocedure),E'\r\n',E'\n');marker:=' if existing is not null then return(existing->>''revision'')::bigint;end if;';
 if position(marker in definition)=0 then raise exception 'Event revision contract missing';end if;
 execute replace(definition,marker,marker||E'\n'||' if change_scope in (''all'',''forward'') and exists(select 1 from internal.booking_series_plans p join core.events e on e.recurrence_id=p.recurrence_id where e.id=target_event_id and internal.actor_can_manage_event(e.id) is true) then raise invalid_parameter_value using message=''series_plan_requires_combined'';end if;'||E'\n');
 definition:=pg_get_functiondef('internal.booking_json(core.booking_bookings,text)'::regprocedure);marker:='''series_id'', booking.series_id,';
 if position(marker in definition)=0 then raise exception 'Booking JSON contract missing';end if;
 execute replace(definition,marker,marker||E'\n ''future_plan_id'',(select p.id from internal.booking_series_plans p where p.series_id=booking.series_id or p.recurrence_id=(select recurrence_id from core.events where id=booking.event_id)),');
end;$hooks$;

alter function internal.cancel_booking_series_for_actor(uuid) rename to cancel_booking_series_without_plan_for_actor;
revoke all on function internal.cancel_booking_series_without_plan_for_actor(uuid) from public,anon,authenticated;
create function internal.cancel_booking_series_for_actor(target_series_id uuid) returns integer
language plpgsql security definer set search_path='' as $$
declare n integer;
begin
 n:=internal.cancel_booking_series_without_plan_for_actor(target_series_id);
 update internal.booking_series_plans set state='paused',configuration=jsonb_set(configuration,'{automatic}','false'::jsonb),revision=revision+1 where series_id=target_series_id;
 return n;
end;$$;
revoke all on function internal.cancel_booking_series_for_actor(uuid) from public,anon,authenticated;
create or replace function api.cancel_booking_series(target_series_id uuid) returns integer
language sql security definer set search_path='' as $$select internal.cancel_booking_series_for_actor(target_series_id)$$;

do $$ begin execute pg_get_functiondef('api.preview_booking_change(uuid,text,timestamptz,timestamptz,uuid[],uuid[])'::regprocedure);execute pg_get_functiondef('api.cancel_booking_series(uuid)'::regprocedure);execute pg_get_functiondef('internal.execute_booking_command_for_actor(uuid,text,jsonb,jsonb)'::regprocedure);end;$$;
