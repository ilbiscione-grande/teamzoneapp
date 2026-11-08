-- Explicit booking-side time changes. No reverse synchronization trigger:
-- activity moves reuse the existing event command and its booking trigger.
create function internal.preview_booking_time_for_actor(target_booking_id uuid, change_scope text,
 new_starts_at timestamptz,new_ends_at timestamptz) returns jsonb
language plpgsql security definer set search_path='' as $$
declare anchor core.booking_bookings; activity core.events; ids uuid[]; org uuid;
 booked_row core.booking_bookings; resource_row core.booking_resources; rows jsonb:='[]'; resource_versions jsonb;
 delta_start interval; delta_end interval; ns timestamptz; ne timestamptz; next_status text;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 if change_scope is null or change_scope not in ('booking','group','event')
  or new_starts_at is null or new_ends_at is null or new_ends_at<=new_starts_at
  or new_ends_at-new_starts_at>interval '31 days' or new_ends_at<=now() then
  raise invalid_parameter_value using message='invalid_time';end if;
 select * into anchor from core.booking_bookings where id=target_booking_id;
 if anchor.id is null or internal.booking_actor_can_cancel(anchor) is not true
  or (internal.booking_actor_role(anchor.organization_id) is null
   and internal.booking_actor_leads_team(anchor.organization_id,anchor.team_id) is not true) then
  raise insufficient_privilege using message='not_allowed';end if;
 -- Same lock order as event revision: series, event, organisations, bookings.
 if anchor.event_id is not null then
  perform pg_advisory_xact_lock(hashtextextended('event-series:'||coalesce(
   (select recurrence_id from core.events where id=anchor.event_id),anchor.event_id)::text,0));
  select * into activity from core.events where id=anchor.event_id for update;
  if activity.id is null or activity.state not in ('draft','scheduled') or activity.archived_at is not null then
   raise check_violation using message='event_not_found';end if;
 end if;
 if change_scope='event' and (activity.id is null or internal.actor_can_manage_event(activity.id) is not true) then
  raise insufficient_privilege using message='event_move_not_allowed';end if;
 if change_scope='group' and anchor.group_id is null then raise invalid_parameter_value using message='invalid_command';end if;
 for org in select distinct b.organization_id from core.booking_bookings b
  where b.id=anchor.id or (change_scope='group' and b.group_id=anchor.group_id)
   or (change_scope='event' and b.event_id=anchor.event_id) order by b.organization_id loop
  perform internal.lock_booking_organization(org);
 end loop;
 -- Reread after waiting: cancellation and approval can change the row meanwhile.
 select * into anchor from core.booking_bookings where id=target_booking_id for update;
 if internal.booking_actor_can_cancel(anchor) is not true or (internal.booking_actor_role(anchor.organization_id) is null
  and internal.booking_actor_leads_team(anchor.organization_id,anchor.team_id) is not true) then
  raise insufficient_privilege using message='not_allowed';end if;
 select array_agg(b.id order by b.id) into ids from core.booking_bookings b
  where b.status in ('pending','confirmed') and b.ends_at>now() and
   (b.id=anchor.id or (change_scope='group' and b.group_id=anchor.group_id)
    or (change_scope='event' and b.event_id=anchor.event_id));
 if ids is null then raise invalid_parameter_value using message='not_active';end if;
 perform 1 from core.booking_bookings b where b.id=any(ids) order by b.id for update;
 if change_scope<>'event' and exists(select 1 from core.booking_bookings b where b.id=any(ids)
  and (internal.booking_actor_can_cancel(b) is not true or b.event_id is distinct from anchor.event_id
   or (internal.booking_actor_role(b.organization_id) is null and internal.booking_actor_leads_team(b.organization_id,b.team_id) is not true))) then
  raise insufficient_privilege using message='not_allowed';end if;
 delta_start:=new_starts_at-case when change_scope='event' then activity.starts_at else anchor.starts_at end;
 delta_end:=new_ends_at-case when change_scope='event' then activity.ends_at else anchor.ends_at end;
 for booked_row in select * from core.booking_bookings where id=any(ids) order by id loop
  select * into resource_row from core.booking_resources where id=booked_row.resource_id;
  ns:=booked_row.starts_at+delta_start;ne:=booked_row.ends_at+delta_end;
  if not resource_row.active then raise check_violation using message='resource_inactive';end if;
  if ne<=ns or ne-ns>interval '31 days' or ne<=now() then raise check_violation using message='invalid_time';end if;
  if not internal.booking_within_disposition(resource_row,ns,ne) then
   raise check_violation using message='resource_outside_disposition',detail=jsonb_build_object('resource_name',resource_row.name)::text;end if;
  if exists(select 1 from core.booking_bookings other where other.status in ('pending','confirmed')
   and not(other.id=any(ids)) and other.organization_id=booked_row.organization_id
   and other.starts_at<ne and other.ends_at>ns and internal.booking_resources_overlap(booked_row.resource_id,other.resource_id)) then
   raise exclusion_violation using message='resource_busy',detail=jsonb_build_object('resource_name',resource_row.name)::text;end if;
  next_status:=case when (ns,ne) is distinct from (booked_row.starts_at,booked_row.ends_at) and resource_row.requires_approval
   and internal.booking_actor_role(booked_row.organization_id) is distinct from 'admin' then 'pending' else booked_row.status end;
  rows:=rows||jsonb_build_array(jsonb_build_object('id',booked_row.id,'revision',booked_row.revision,'resource_id',resource_row.id,
   'resource_name',resource_row.name,'organization_id',booked_row.organization_id,'old_starts_at',booked_row.starts_at,'old_ends_at',booked_row.ends_at,
   'starts_at',ns,'ends_at',ne,'old_status',booked_row.status,'status',next_status));
 end loop;
 if exists(select 1 from jsonb_array_elements(rows) a join jsonb_array_elements(rows) b on a->>'id'<b->>'id'
  where a->>'organization_id'=b->>'organization_id' and (a->>'starts_at')::timestamptz<(b->>'ends_at')::timestamptz
   and (a->>'ends_at')::timestamptz>(b->>'starts_at')::timestamptz
   and internal.booking_resources_overlap((a->>'resource_id')::uuid,(b->>'resource_id')::uuid)) then
  raise exclusion_violation using message='resource_busy';end if;
 -- Snapshot ancestor revisions too: changed availability invalidates the preview.
 select jsonb_object_agg(r.id::text,r.revision) into resource_versions from core.booking_resources r
 where r.id in(select a.id from core.booking_bookings b cross join lateral internal.booking_resource_ancestors(b.resource_id) a where b.id=any(ids));
 return jsonb_build_object('target_booking_id',anchor.id,'scope',change_scope,'starts_at',new_starts_at,'ends_at',new_ends_at,
  'event_id',activity.id,'event_revision',activity.revision,'event_starts_at',activity.starts_at,'event_ends_at',activity.ends_at,
  'resources',resource_versions,'bookings',rows);
end; $$;
revoke all on function internal.preview_booking_time_for_actor(uuid,text,timestamptz,timestamptz) from public,anon,authenticated;

create function api.preview_booking_time(target_booking_id uuid, change_scope text,new_starts_at timestamptz,new_ends_at timestamptz)
returns jsonb language plpgsql security definer set search_path='' as $$
begin return internal.preview_booking_time_for_actor(target_booking_id,change_scope,new_starts_at,new_ends_at);end; $$;
revoke all on function api.preview_booking_time(uuid,text,timestamptz,timestamptz) from public,anon,authenticated;
grant execute on function api.preview_booking_time(uuid,text,timestamptz,timestamptz) to authenticated;

create function internal.reschedule_booking_for_actor(p jsonb, command_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare plan jsonb; item jsonb; previous core.booking_bookings; changed uuid[]:='{}'; requests uuid[]:='{}'; notice record;
begin
 if jsonb_typeof(p->'expected_plan') is distinct from 'object' then raise invalid_parameter_value using message='revision_required';end if;
 plan:=internal.preview_booking_time_for_actor((p->>'target_booking_id')::uuid,p->>'change_scope',
  (p->>'new_starts_at')::timestamptz,(p->>'new_ends_at')::timestamptz);
 if plan is distinct from p->'expected_plan' then raise sqlstate 'PT409' using message='stale_revision';end if;
 if plan->>'scope'='event' then
  -- Reuse event authorization, revision, audit, outbox and atomic booking sync.
  perform internal.revise_event_v2_for_actor((plan->>'event_id')::uuid,'one',
   jsonb_build_object('starts_at',plan->'starts_at','ends_at',plan->'ends_at'),(plan->>'event_revision')::bigint,md5('booking-time:'||command_id::text)::uuid);
 else
  for item in select value from jsonb_array_elements(plan->'bookings') order by
   case when (value->>'starts_at')::timestamptz >= (value->>'old_starts_at')::timestamptz then (value->>'old_starts_at')::timestamptz end desc,
   (value->>'old_starts_at')::timestamptz,value->>'id' loop
   if (item->>'starts_at',item->>'ends_at') is not distinct from (item->>'old_starts_at',item->>'old_ends_at') then continue;end if;
   select * into previous from core.booking_bookings where id=(item->>'id')::uuid;
   update core.booking_bookings set starts_at=(item->>'starts_at')::timestamptz,ends_at=(item->>'ends_at')::timestamptz,
    status=item->>'status',revision=revision+1,
    decided_by=case when item->>'status'='pending' then null else decided_by end,
    decided_at=case when item->>'status'='pending' then null else decided_at end where id=previous.id;
   changed:=array_append(changed,previous.id);
   if previous.status='confirmed' and item->>'status'='pending' then requests:=array_append(requests,previous.id);end if;
  end loop;
  for notice in select distinct on(coalesce(b.group_id,b.id),b.booked_by) b.* from core.booking_bookings b
   where b.id=any(changed) order by coalesce(b.group_id,b.id),b.booked_by,b.id loop
   perform internal.booking_notify(notice.id,'rescheduled',array[notice.booked_by]);
  end loop;
  for notice in select distinct on(coalesce(b.group_id,b.id)) b.* from core.booking_bookings b
   where b.id=any(requests) order by coalesce(b.group_id,b.id),b.id loop
   perform internal.booking_notify(notice.id,'requested',array(select profile_id from internal.booking_admin_profiles(notice.organization_id)));
  end loop;
 end if;
 return plan;
end; $$;
revoke all on function internal.reschedule_booking_for_actor(jsonb,uuid) from public,anon,authenticated;

-- Narrow patches preserve any independently updated command cases/JSON fields.
do $patch$
declare definition text; marker text;
begin
 definition:=pg_get_functiondef('internal.execute_booking_command_for_actor(uuid,text,jsonb,jsonb)'::regprocedure);
 marker:='  case command_type';
 if position(marker in definition)=0 then raise exception 'Booking executor patch anchor missing';end if;
 definition:=replace(definition,marker,marker||E'\n    when ''reschedule_booking'' then result := internal.reschedule_booking_for_actor(p,command_id);');
 execute definition;
 definition:=pg_get_functiondef('internal.booking_json(core.booking_bookings,text)'::regprocedure);
 marker:='''event_id'', booking.event_id,';
 if position(marker in definition)=0 then raise exception 'Booking JSON patch anchor missing';end if;
 definition:=replace(definition,marker,marker||E'\n    ''event_starts_at'', (select starts_at from core.events where id=booking.event_id),\n    ''event_ends_at'', (select ends_at from core.events where id=booking.event_id),\n    ''can_move_event'', coalesce(internal.actor_can_manage_event(booking.event_id),false),');
 execute definition;
 definition:=pg_get_functiondef('internal.list_event_bookings_for_actor(uuid)'::regprocedure);
 marker:=' and booking.status in (''pending'', ''confirmed'')';
 if position(marker in definition)=0 then raise exception 'Event bookings patch anchor missing';end if;
 definition:=replace(definition,marker,'');
 execute replace(definition,'''resource_name'', resource.name,','''resource_id'', resource.id, ''resource_name'', resource.name,');
end; $patch$;

do $locks$
declare name text; definition text; predicate text; signature text; marker text;
begin
 foreach name in array array['cancel_booking','decide_booking','cancel_booking_group','decide_booking_group','cancel_booking_series','decide_booking_series'] loop
  signature:='internal.'||name||'_for_actor(uuid'||case when name like 'decide_%' then ',boolean' else '' end||')';
  predicate:=case when name like '%_group' then 'b.group_id=target_group_id' when name like '%_series' then 'b.series_id=target_series_id' else 'b.id=target_booking_id' end;
  definition:=pg_get_functiondef(signature::regprocedure);
  marker:=E'begin\n';
  definition:=replace(definition,E'\r\n',E'\n');
  if position(marker in definition)=0 then raise exception 'Booking lock patch anchor missing: %',name;end if;
  definition:=replace(definition,marker,marker||' perform internal.lock_booking_organization(o.organization_id) from (select distinct b.organization_id from core.booking_bookings b where '||predicate||' order by b.organization_id) o;'||E'\n');
  execute definition;
 end loop;
 definition:=pg_get_functiondef('internal.execute_booking_command_for_actor(uuid,text,jsonb,jsonb)'::regprocedure);
 marker:='    perform 1 from core.booking_bookings b where b.id = any(affected) order by b.id for update;';
 if position(marker in definition)=0 then raise exception 'Executor lock patch anchor missing';end if;
 execute replace(definition,marker,'    perform internal.lock_booking_organization(o.organization_id) from (select distinct b.organization_id from core.booking_bookings b where b.id=any(affected) order by b.organization_id) o;'||E'\n'||marker);
end; $locks$;
