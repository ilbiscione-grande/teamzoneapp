-- Extend the existing locked, revision-bound engine to all materialized future occurrences.
create or replace function internal.preview_booking_forward_for_actor(target_booking_id uuid,change_scope text,
 new_starts_at timestamptz,new_ends_at timestamptz) returns jsonb
language plpgsql security definer set search_path='' as $$
declare anchor core.booking_bookings; activity core.events; series core.booking_series;
 event_ids uuid[]:='{}'; booking_ids uuid[]:='{}'; org uuid; zone text;
 start_shift interval; end_shift interval; event_rows jsonb:='[]'; booking_rows jsonb:='[]'; versions jsonb;
 occurrence core.events; booked core.booking_bookings; resource core.booking_resources; projected jsonb;
 ns timestamptz; ne timestamptz; local_start timestamp; local_end timestamp; next_status text; conflicts jsonb:='[]';
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 if change_scope is null or change_scope not in ('series_forward','event_forward','series_all','event_all')
  or new_starts_at is null or new_ends_at is null or new_ends_at<=new_starts_at
  or new_ends_at-new_starts_at>interval '31 days' or new_starts_at<=now() then
  raise invalid_parameter_value using message='invalid_time';end if;
 select * into anchor from core.booking_bookings where id=target_booking_id;
 if anchor.id is null or internal.booking_actor_can_cancel(anchor) is not true
  or (internal.booking_actor_role(anchor.organization_id) is null and internal.booking_actor_leads_team(anchor.organization_id,anchor.team_id) is not true) then
  raise insufficient_privilege using message='not_allowed';end if;
 if anchor.starts_at<=now() then raise invalid_parameter_value using message='forward_requires_future';end if;
 if change_scope in ('series_forward','series_all') then
  if anchor.series_id is null or anchor.event_id is not null then raise invalid_parameter_value using message='forward_series_not_found';end if;
  perform pg_advisory_xact_lock(hashtextextended('booking-series:'||anchor.series_id::text,0));
  select * into series from core.booking_series where id=anchor.series_id;
  if series.id is null then raise invalid_parameter_value using message='forward_series_not_found';end if;
  zone:=series.timezone;
  perform internal.lock_booking_organization(anchor.organization_id);
 else
  select * into activity from core.events where id=anchor.event_id;
  if activity.id is null or activity.recurrence_id is null then raise invalid_parameter_value using message='forward_series_not_found';end if;
  perform pg_advisory_xact_lock(hashtextextended('event-series:'||activity.recurrence_id::text,0));
  select * into activity from core.events where id=anchor.event_id for update;
  if activity.starts_at<=now() or activity.archived_at is not null or activity.state not in ('draft','scheduled') then
   raise invalid_parameter_value using message='forward_requires_future';end if;
  if internal.actor_can_manage_event(activity.id) is not true then raise insufficient_privilege using message='event_move_not_allowed';end if;
  select array_agg(e.id order by e.occurrence_number,e.id) into event_ids from core.events e
   where e.recurrence_id=activity.recurrence_id and (change_scope='event_all' or e.occurrence_number>=activity.occurrence_number)
    and e.starts_at>now() and e.archived_at is null and e.state in ('draft','scheduled');
  perform 1 from core.events e where e.id=any(event_ids) order by e.occurrence_number,e.id for update;
  if exists(select 1 from core.events e where e.id=any(event_ids) and internal.actor_can_manage_event(e.id) is not true) then
   raise insufficient_privilege using message='event_move_not_allowed';end if;
  zone:=activity.timezone;
  for org in select distinct b.organization_id from core.booking_bookings b where b.event_id=any(event_ids) order by b.organization_id loop
   perform internal.lock_booking_organization(org);
  end loop;
 end if;
 -- Decisions, cancellations and single-time moves share the organisation gate.
 select * into anchor from core.booking_bookings where id=target_booking_id for update;
 if internal.booking_actor_can_cancel(anchor) is not true or anchor.starts_at<=now() then
  raise insufficient_privilege using message='not_allowed';end if;
 if change_scope in ('series_forward','series_all') then
  select array_agg(b.id order by b.id) into booking_ids from core.booking_bookings b
   where b.series_id=anchor.series_id and (change_scope='series_all' or b.series_sequence>=anchor.series_sequence) and b.starts_at>now() and b.status in ('pending','confirmed');
 else
  select array_agg(b.id order by b.id) into booking_ids from core.booking_bookings b
   where b.event_id=any(event_ids) and b.ends_at>now() and b.status in ('pending','confirmed');
 end if;
 booking_ids:=coalesce(booking_ids,'{}'::uuid[]);
 perform 1 from core.booking_bookings b where b.id=any(booking_ids) order by b.id for update;
 if change_scope in ('series_forward','series_all') and exists(select 1 from core.booking_bookings b where b.id=any(booking_ids)
  and (b.event_id is not null or b.organization_id<>anchor.organization_id or internal.booking_actor_can_cancel(b) is not true)) then
  raise insufficient_privilege using message='not_allowed';end if;
 start_shift:=(new_starts_at at time zone zone)-(case when change_scope in ('event_forward','event_all') then activity.starts_at else anchor.starts_at end at time zone zone);
 end_shift:=(new_ends_at at time zone zone)-(case when change_scope in ('event_forward','event_all') then activity.ends_at else anchor.ends_at end at time zone zone);
 if change_scope in ('event_forward','event_all') then
  for occurrence in select * from core.events where id=any(event_ids) order by occurrence_number,id loop
   -- Recheck lifecycle after row-lock waits. Cancelled/archived occurrences stay unchanged.
   if occurrence.starts_at<=now() or occurrence.archived_at is not null or occurrence.state not in ('draft','scheduled') then continue;end if;
   local_start:=(occurrence.starts_at at time zone occurrence.timezone)+start_shift;
   local_end:=(occurrence.ends_at at time zone occurrence.timezone)+end_shift;
   ns:=local_start at time zone occurrence.timezone;ne:=local_end at time zone occurrence.timezone;
   if (ns at time zone occurrence.timezone)<>local_start or (ne at time zone occurrence.timezone)<>local_end
    or (occurrence.id=activity.id and (ns,ne) is distinct from (new_starts_at,new_ends_at)) then
    raise invalid_parameter_value using message='forward_invalid_local_time';end if;
   if ns<=now() or ne<=ns then raise invalid_parameter_value using message='invalid_time';end if;
   event_rows:=event_rows||jsonb_build_array(jsonb_build_object('id',occurrence.id,'title',occurrence.title,'revision',occurrence.revision,
    'timezone',occurrence.timezone,'occurrence_number',occurrence.occurrence_number,'old_starts_at',occurrence.starts_at,'old_ends_at',occurrence.ends_at,'starts_at',ns,'ends_at',ne));
  end loop;
 end if;
 for booked in select * from core.booking_bookings where id=any(booking_ids) order by id loop
  select * into resource from core.booking_resources where id=booked.resource_id;
  if change_scope in ('event_forward','event_all') then
   select value into projected from jsonb_array_elements(event_rows) where value->>'id'=booked.event_id::text;
   if projected is null then continue;end if;
   ns:=(projected->>'starts_at')::timestamptz+(booked.starts_at-(projected->>'old_starts_at')::timestamptz);
   ne:=(projected->>'ends_at')::timestamptz+(booked.ends_at-(projected->>'old_ends_at')::timestamptz);
  else
   local_start:=(booked.starts_at at time zone zone)+start_shift;local_end:=(booked.ends_at at time zone zone)+end_shift;
   ns:=local_start at time zone zone;ne:=local_end at time zone zone;
   if (ns at time zone zone)<>local_start or (ne at time zone zone)<>local_end
    or (booked.id=anchor.id and (ns,ne) is distinct from (new_starts_at,new_ends_at)) then
    raise invalid_parameter_value using message='forward_invalid_local_time';end if;
  end if;
  if not resource.active then conflicts:=conflicts||jsonb_build_array(jsonb_build_object('resource_name',resource.name,'starts_at',ns,'reason','resource_inactive'));end if;
  if ne<=ns or ne-ns>interval '31 days' or ne<=now() or (change_scope in ('series_forward','series_all') and ns<=now()) then
   conflicts:=conflicts||jsonb_build_array(jsonb_build_object('resource_name',resource.name,'starts_at',ns,'reason','invalid_time'));
  elsif not internal.booking_within_disposition(resource,ns,ne) then
   conflicts:=conflicts||jsonb_build_array(jsonb_build_object('resource_name',resource.name,'starts_at',ns,'reason','resource_outside_disposition'));end if;
  if ne>ns and exists(select 1 from core.booking_bookings b where b.status in ('pending','confirmed') and b.organization_id=booked.organization_id
   and not(b.id=any(booking_ids)) and b.starts_at<ne and b.ends_at>ns and internal.booking_resources_overlap(booked.resource_id,b.resource_id)) then
   conflicts:=conflicts||jsonb_build_array(jsonb_build_object('resource_name',resource.name,'starts_at',ns,'reason','resource_busy'));end if;
  next_status:=case when (ns,ne) is distinct from (booked.starts_at,booked.ends_at) and resource.requires_approval
   and internal.booking_actor_role(booked.organization_id) is distinct from 'admin' then 'pending' else booked.status end;
  booking_rows:=booking_rows||jsonb_build_array(jsonb_build_object('id',booked.id,'revision',booked.revision,'event_id',booked.event_id,
   'resource_id',resource.id,'resource_name',resource.name,'organization_id',booked.organization_id,'series_sequence',booked.series_sequence,
   'old_starts_at',booked.starts_at,'old_ends_at',booked.ends_at,'starts_at',ns,'ends_at',ne,'old_status',booked.status,'status',next_status));
 end loop;
 select conflicts||coalesce(jsonb_agg(distinct jsonb_build_object('resource_name',a->>'resource_name','starts_at',a->'starts_at','reason','resource_busy')),'[]'::jsonb)
 into conflicts from jsonb_array_elements(booking_rows) a join jsonb_array_elements(booking_rows) b on a->>'id'<b->>'id'
  where a->>'organization_id'=b->>'organization_id' and (a->>'starts_at')::timestamptz<(b->>'ends_at')::timestamptz
   and (a->>'ends_at')::timestamptz>(b->>'starts_at')::timestamptz
   and internal.booking_resources_overlap((a->>'resource_id')::uuid,(b->>'resource_id')::uuid);
 select jsonb_object_agg(r.id::text,r.revision) into versions from core.booking_resources r where r.id in
  (select a.id from core.booking_bookings b cross join lateral internal.booking_resource_ancestors(b.resource_id) a where b.id=any(booking_ids));
 return jsonb_build_object('target_booking_id',anchor.id,'scope',change_scope,'starts_at',new_starts_at,'ends_at',new_ends_at,
  'series_id',series.id,'series_sequence',anchor.series_sequence,'timezone',zone,'event_id',activity.id,
  'event_starts_at',activity.starts_at,'event_ends_at',activity.ends_at,'resources',versions,'events',event_rows,'bookings',booking_rows,'conflicts',conflicts);
end; $$;
revoke all on function internal.preview_booking_forward_for_actor(uuid,text,timestamptz,timestamptz) from public,anon,authenticated;

create or replace function internal.reschedule_booking_forward_for_actor(p jsonb,command_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare plan jsonb; item jsonb; previous core.booking_bookings; changed uuid[]:='{}'; requests uuid[]:='{}'; notice record;
begin
 if jsonb_typeof(p->'expected_plan') is distinct from 'object' then raise invalid_parameter_value using message='revision_required';end if;
 plan:=internal.preview_booking_forward_for_actor((p->>'target_booking_id')::uuid,p->>'change_scope',(p->>'new_starts_at')::timestamptz,(p->>'new_ends_at')::timestamptz);
 if jsonb_array_length(plan->'conflicts')>0 then raise check_violation using message='forward_conflicts';end if;
 if plan is distinct from p->'expected_plan' then raise sqlstate 'PT409' using message='stale_revision';end if;
 if plan->>'scope' in ('event_forward','event_all') then
  for item in select value from jsonb_array_elements(plan->'events') order by
   case when (value->>'starts_at')::timestamptz >= (value->>'old_starts_at')::timestamptz then (value->>'old_starts_at')::timestamptz end desc,
   (value->>'old_starts_at')::timestamptz,value->>'id' loop
   perform internal.revise_event_v2_for_actor((item->>'id')::uuid,'one',jsonb_build_object('starts_at',item->'starts_at','ends_at',item->'ends_at'),
    (item->>'revision')::bigint,md5('booking-forward:'||command_id::text||':'||(item->>'id'))::uuid);
  end loop;
 else
  for item in select value from jsonb_array_elements(plan->'bookings') order by
   case when (value->>'starts_at')::timestamptz >= (value->>'old_starts_at')::timestamptz then (value->>'old_starts_at')::timestamptz end desc,
   (value->>'old_starts_at')::timestamptz,value->>'id' loop
   if (item->>'starts_at',item->>'ends_at') is not distinct from (item->>'old_starts_at',item->>'old_ends_at') then continue;end if;
   select * into previous from core.booking_bookings where id=(item->>'id')::uuid;
   update core.booking_bookings set starts_at=(item->>'starts_at')::timestamptz,ends_at=(item->>'ends_at')::timestamptz,
    status=item->>'status',revision=revision+1,decided_by=case when item->>'status'='pending' then null else decided_by end,
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
revoke all on function internal.reschedule_booking_forward_for_actor(jsonb,uuid) from public,anon,authenticated;

do $route$
declare definition text; marker text; replacement text;
begin
 marker:='in (''series_forward'',''event_forward'')';
 replacement:='in (''series_forward'',''event_forward'',''series_all'',''event_all'')';
 definition:=pg_get_functiondef('internal.preview_booking_time_for_actor(uuid,text,timestamptz,timestamptz)'::regprocedure);
 if position(marker in definition)=0 then raise exception 'Preview route anchor missing';end if;
 execute replace(definition,marker,replacement);
 definition:=pg_get_functiondef('internal.reschedule_booking_for_actor(jsonb,uuid)'::regprocedure);
 if position(marker in definition)=0 then raise exception 'Reschedule route anchor missing';end if;
 execute replace(definition,marker,replacement);
 definition:=pg_get_functiondef('internal.booking_json(core.booking_bookings,text)'::regprocedure);
 marker:='''series_sequence'',booking.series_sequence,';
 if position(marker in definition)=0 then raise exception 'Booking JSON anchor missing';end if;
 execute replace(definition,marker,marker||E'\n ''series_upcoming_remaining'',case when booking.starts_at>now() then (select count(*) from core.booking_bookings b where b.series_id=booking.series_id and b.starts_at>now() and b.status in (''pending'',''confirmed'')) else 0 end,\n ''event_upcoming_remaining'',case when internal.actor_can_manage_event(booking.event_id) is true then (select count(*) from core.events e join core.events a on a.id=booking.event_id where a.starts_at>now() and e.recurrence_id=a.recurrence_id and e.starts_at>now() and e.archived_at is null and e.state in (''draft'',''scheduled'')) else 0 end,');
end; $route$;
