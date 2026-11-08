-- Extend the existing locked, revision-bound engine to all materialized future occurrences.
create or replace function internal.preview_booking_change_times_for_actor(target_booking_id uuid,change_scope text,
 new_starts_at timestamptz,new_ends_at timestamptz) returns jsonb
language plpgsql security definer set search_path='' as $$
declare anchor core.booking_bookings; activity core.events; series core.booking_series;
 event_ids uuid[]:='{}'; booking_ids uuid[]:='{}'; org uuid; zone text;
 start_shift interval; end_shift interval; event_rows jsonb:='[]'; booking_rows jsonb:='[]'; versions jsonb;
 occurrence core.events; booked core.booking_bookings; resource core.booking_resources; projected jsonb;
 ns timestamptz; ne timestamptz; local_start timestamp; local_end timestamp; next_status text; conflicts jsonb:='[]';
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 if change_scope is null or change_scope not in ('group','event','series_forward','event_forward','series_all','event_all')
  or new_starts_at is null or new_ends_at is null or new_ends_at<=new_starts_at
  or new_ends_at-new_starts_at>interval '31 days' or new_starts_at<=now() then
  raise invalid_parameter_value using message='invalid_time';end if;
 select * into anchor from core.booking_bookings where id=target_booking_id;
 if anchor.id is null or internal.booking_actor_can_cancel(anchor) is not true
  or (internal.booking_actor_role(anchor.organization_id) is null and internal.booking_actor_leads_team(anchor.organization_id,anchor.team_id) is not true) then
  raise insufficient_privilege using message='not_allowed';end if;
 if anchor.starts_at<=now() then raise invalid_parameter_value using message='forward_requires_future';end if;
 if change_scope in ('group','series_forward','series_all') then
  if change_scope<>'group' and (anchor.series_id is null or anchor.event_id is not null) then raise invalid_parameter_value using message='forward_series_not_found';end if;
  if anchor.series_id is not null then perform pg_advisory_xact_lock(hashtextextended('booking-series:'||anchor.series_id::text,0));end if;
  select * into series from core.booking_series where id=anchor.series_id;
  if change_scope<>'group' and series.id is null then raise invalid_parameter_value using message='forward_series_not_found';end if;
  zone:=coalesce(series.timezone,(select timezone from core.booking_resources where id=anchor.resource_id));
  perform internal.lock_booking_organization(anchor.organization_id);
 else
  select * into activity from core.events where id=anchor.event_id;
  if activity.id is null or (change_scope<>'event' and activity.recurrence_id is null) then raise invalid_parameter_value using message='forward_series_not_found';end if;
  perform pg_advisory_xact_lock(hashtextextended('event-series:'||coalesce(activity.recurrence_id,activity.id)::text,0));
  select * into activity from core.events where id=anchor.event_id for update;
  if activity.starts_at<=now() or activity.archived_at is not null or activity.state not in ('draft','scheduled') then
   raise invalid_parameter_value using message='forward_requires_future';end if;
  if internal.actor_can_manage_event(activity.id) is not true then raise insufficient_privilege using message='event_move_not_allowed';end if;
  select array_agg(e.id order by e.occurrence_number,e.id) into event_ids from core.events e
   where ((change_scope='event' and e.id=activity.id) or (change_scope<>'event' and e.recurrence_id=activity.recurrence_id and (change_scope='event_all' or e.occurrence_number>=activity.occurrence_number)))
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
 if change_scope in ('group','series_forward','series_all') then
  select array_agg(b.id order by b.id) into booking_ids from core.booking_bookings b
   where ((change_scope='group' and (b.id=anchor.id or b.group_id=anchor.group_id)) or (change_scope<>'group' and b.series_id=anchor.series_id and (change_scope='series_all' or b.series_sequence>=anchor.series_sequence))) and b.starts_at>now() and b.status in ('pending','confirmed');
 else
  select array_agg(b.id order by b.id) into booking_ids from core.booking_bookings b
   where b.event_id=any(event_ids) and b.ends_at>now() and b.status in ('pending','confirmed');
 end if;
 booking_ids:=coalesce(booking_ids,'{}'::uuid[]);
 perform 1 from core.booking_bookings b where b.id=any(booking_ids) order by b.id for update;
 if change_scope in ('group','series_forward','series_all') and exists(select 1 from core.booking_bookings b where b.id=any(booking_ids)
  and (b.event_id is distinct from anchor.event_id or b.organization_id<>anchor.organization_id or internal.booking_actor_can_cancel(b) is not true)) then
  raise insufficient_privilege using message='not_allowed';end if;
 start_shift:=(new_starts_at at time zone zone)-(case when change_scope in ('event','event_forward','event_all') then activity.starts_at else anchor.starts_at end at time zone zone);
 end_shift:=(new_ends_at at time zone zone)-(case when change_scope in ('event','event_forward','event_all') then activity.ends_at else anchor.ends_at end at time zone zone);
 if change_scope in ('event','event_forward','event_all') then
  for occurrence in select * from core.events where id=any(event_ids) order by occurrence_number,id loop
   -- Recheck lifecycle after row-lock waits. Cancelled/archived occurrences stay unchanged.
   if occurrence.starts_at<=now() or occurrence.archived_at is not null or occurrence.state not in ('draft','scheduled') then continue;end if;
   local_start:=(occurrence.starts_at at time zone occurrence.timezone)+start_shift;
   local_end:=(occurrence.ends_at at time zone occurrence.timezone)+end_shift;
   ns:=local_start at time zone occurrence.timezone;ne:=local_end at time zone occurrence.timezone;
   if (ns at time zone occurrence.timezone)<>local_start or (ne at time zone occurrence.timezone)<>local_end
    or (occurrence.id=activity.id and (ns,ne) is distinct from (new_starts_at,new_ends_at)) then
    raise invalid_parameter_value using message='forward_invalid_local_time';end if;
   if exists(select 1 from generate_series(-120,120,15) x where x<>0 and ((ns+x*interval '1 minute') at time zone occurrence.timezone=local_start or (ne+x*interval '1 minute') at time zone occurrence.timezone=local_end)) then raise invalid_parameter_value using message='forward_invalid_local_time';end if;
   if ns<=now() or ne<=ns or ne-ns>interval '31 days' then raise invalid_parameter_value using message='invalid_time';end if;
   event_rows:=event_rows||jsonb_build_array(jsonb_build_object('id',occurrence.id,'title',occurrence.title,'revision',occurrence.revision,
    'timezone',occurrence.timezone,'occurrence_number',occurrence.occurrence_number,'old_starts_at',occurrence.starts_at,'old_ends_at',occurrence.ends_at,'starts_at',ns,'ends_at',ne));
  end loop;
 end if;
 for booked in select * from core.booking_bookings where id=any(booking_ids) order by id loop
  select * into resource from core.booking_resources where id=booked.resource_id;
  if change_scope in ('event','event_forward','event_all') then
   select value into projected from jsonb_array_elements(event_rows) where value->>'id'=booked.event_id::text;
   if projected is null then continue;end if;
   ns:=(projected->>'starts_at')::timestamptz+(booked.starts_at-(projected->>'old_starts_at')::timestamptz);
   ne:=(projected->>'ends_at')::timestamptz+(booked.ends_at-(projected->>'old_ends_at')::timestamptz);
  else
   if change_scope='group' then
   ns:=booked.starts_at+(new_starts_at-anchor.starts_at);ne:=booked.ends_at+(new_ends_at-anchor.ends_at);
   else
   local_start:=(booked.starts_at at time zone zone)+start_shift;local_end:=(booked.ends_at at time zone zone)+end_shift;
   ns:=local_start at time zone zone;ne:=local_end at time zone zone;
   if exists(select 1 from generate_series(-120,120,15) x where x<>0 and ((ns+x*interval '1 minute') at time zone zone=local_start or (ne+x*interval '1 minute') at time zone zone=local_end)) then raise invalid_parameter_value using message='forward_invalid_local_time';end if;
   if (ns at time zone zone)<>local_start or (ne at time zone zone)<>local_end
    or (booked.id=anchor.id and (ns,ne) is distinct from (new_starts_at,new_ends_at)) then
    raise invalid_parameter_value using message='forward_invalid_local_time';end if;
   end if;
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
revoke all on function internal.preview_booking_change_times_for_actor(uuid,text,timestamptz,timestamptz) from public,anon,authenticated;


-- One reviewed command changes time and the resource set atomically.
create function internal.preview_booking_change_for_actor(target_booking_id uuid,change_scope text,
 new_starts_at timestamptz,new_ends_at timestamptz,add_resource_ids uuid[],remove_resource_ids uuid[])
returns jsonb language plpgsql security definer set search_path='' as $$
declare anchor core.booking_bookings; timing jsonb; selection jsonb; ctx jsonb; item jsonb; moved jsonb;
 contexts jsonb:='[]'; adding jsonb; keeping jsonb; final_rows jsonb:='[]'; conflicts jsonb:='[]';
 removed uuid[]; replaced uuid[]; resource core.booking_resources; ns timestamptz; ne timestamptz;
 versions jsonb; n integer; eventrow jsonb;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 if change_scope is null or change_scope not in ('booking','series_forward','series_all','event_forward','event_all') then raise invalid_parameter_value using message='invalid_command';end if;
 select * into anchor from core.booking_bookings where id=target_booking_id;
 -- Project and acquire series/event/organization locks before resource-set locks.
 timing:=internal.preview_booking_change_times_for_actor(target_booking_id,
  case when change_scope='booking' then case when anchor.event_id is null then 'group' else 'event' end else change_scope end,new_starts_at,new_ends_at);
 selection:=internal.preview_booking_resources_for_actor(target_booking_id,change_scope,add_resource_ids,remove_resource_ids);
 select coalesce(jsonb_agg(v),'[]') into conflicts from jsonb_array_elements(selection->'conflicts') v where v->>'reason'='resource_change_requires_future';
 select coalesce(array_agg((b->>'id')::uuid),'{}') into removed from jsonb_array_elements(selection->'contexts') c cross join lateral jsonb_array_elements(c->'remove') b;
 select coalesce(array_agg((b->>'id')::uuid),'{}') into replaced from jsonb_array_elements(timing->'bookings') b;
 -- Removed bookings have no projected claim. Revalidate the complete final state,
 -- including resources in manually changed occurrences and other activity groups.
 for item in select value from jsonb_array_elements(timing->'bookings') loop
  if (item->>'id')::uuid=any(removed) then continue;end if;
  final_rows:=final_rows||jsonb_build_array(item);
 end loop;
 for ctx in select value from jsonb_array_elements(selection->'contexts') loop
  select value into moved from jsonb_array_elements(timing->'bookings') where value->>'id'=ctx->>'anchor_booking_id';
  if moved is null then raise sqlstate 'PT409' using message='stale_revision';end if;
  adding:='[]';keeping:='[]';
  for item in select value from jsonb_array_elements(ctx->'add') loop
   item:=item||jsonb_build_object('organization_id',anchor.organization_id,'starts_at',moved->'starts_at','ends_at',moved->'ends_at',
    'key','new:'||(ctx->>'anchor_booking_id')||':'||(item->>'resource_id'));
   adding:=adding||jsonb_build_array(item);final_rows:=final_rows||jsonb_build_array(item);
  end loop;
  for item in select value from jsonb_array_elements(ctx->'keep') loop
   select value into moved from jsonb_array_elements(timing->'bookings') where value->>'id'=item->>'id';
   keeping:=keeping||jsonb_build_array(item||coalesce(moved,'{}'::jsonb));
  end loop;
  select value into moved from jsonb_array_elements(timing->'bookings') where value->>'id'=ctx->>'anchor_booking_id';
  contexts:=contexts||jsonb_build_array(ctx||jsonb_build_object('add',adding,'keep',keeping,'starts_at',moved->'starts_at','ends_at',moved->'ends_at'));
 end loop;
 for item in select value from jsonb_array_elements(final_rows) loop
  select * into resource from core.booking_resources where id=(item->>'resource_id')::uuid;
  ns:=(item->>'starts_at')::timestamptz;ne:=(item->>'ends_at')::timestamptz;
  if not resource.active then conflicts:=conflicts||jsonb_build_array(jsonb_build_object('resource_name',resource.name,'starts_at',ns,'reason','resource_inactive'));end if;
  if ns<=now() or ne<=ns or ne-ns>interval '31 days' then
   conflicts:=conflicts||jsonb_build_array(jsonb_build_object('resource_name',resource.name,'starts_at',ns,'reason','invalid_time'));
  elsif not internal.booking_within_disposition(resource,ns,ne) then
   conflicts:=conflicts||jsonb_build_array(jsonb_build_object('resource_name',resource.name,'starts_at',ns,'reason','resource_outside_disposition'));end if;
  if exists(select 1 from core.booking_bookings b where b.organization_id=resource.organization_id and b.status in ('pending','confirmed')
   and not(b.id=any(replaced||removed)) and b.starts_at<ne and b.ends_at>ns and internal.booking_resources_overlap(b.resource_id,resource.id)) then
   conflicts:=conflicts||jsonb_build_array(jsonb_build_object('resource_name',resource.name,'starts_at',ns,'reason','resource_busy'));end if;
 end loop;
 select conflicts||coalesce(jsonb_agg(distinct jsonb_build_object('resource_name',a->>'resource_name','starts_at',a->'starts_at','reason','resource_busy')),'[]') into conflicts
 from jsonb_array_elements(final_rows) a join jsonb_array_elements(final_rows) b on coalesce(a->>'id',a->>'key')<coalesce(b->>'id',b->>'key')
 where a->>'organization_id'=b->>'organization_id' and (a->>'starts_at')::timestamptz<(b->>'ends_at')::timestamptz
 and (a->>'ends_at')::timestamptz>(b->>'starts_at')::timestamptz and internal.booking_resources_overlap((a->>'resource_id')::uuid,(b->>'resource_id')::uuid);
 select jsonb_object_agg(r.id::text,r.revision) into versions from core.booking_resources r where r.id in
 (select a.id from jsonb_array_elements(final_rows) v cross join lateral internal.booking_resource_ancestors((v->>'resource_id')::uuid) a);
 select count(*)::int into n from jsonb_array_elements(timing->'bookings') b where not((b->>'id')::uuid=any(removed))
 and (b->>'starts_at',b->>'ends_at') is distinct from (b->>'old_starts_at',b->>'old_ends_at');
 n:=n+(selection->>'change_count')::int;
 for eventrow in select value from jsonb_array_elements(timing->'events') loop
  if (eventrow->>'starts_at',eventrow->>'ends_at') is distinct from (eventrow->>'old_starts_at',eventrow->>'old_ends_at') then n:=n+1;end if;
 end loop;
 return jsonb_build_object('target_booking_id',target_booking_id,'scope',change_scope,'new_starts_at',new_starts_at,'new_ends_at',new_ends_at,
  'add_resource_ids',selection->'add_resource_ids','remove_resource_ids',selection->'remove_resource_ids',
  'selection',selection-'conflicts','timing',timing-'conflicts','contexts',contexts,'final_bookings',final_rows,
  'resources',versions,'conflicts',conflicts,'change_count',n);
end;$$;
revoke all on function internal.preview_booking_change_for_actor(uuid,text,timestamptz,timestamptz,uuid[],uuid[]) from public,anon,authenticated;

create function api.preview_booking_change(target_booking_id uuid,change_scope text,new_starts_at timestamptz,new_ends_at timestamptz,
 add_resource_ids uuid[],remove_resource_ids uuid[]) returns jsonb language plpgsql security definer set search_path='' as $$
begin return internal.preview_booking_change_for_actor(target_booking_id,change_scope,new_starts_at,new_ends_at,add_resource_ids,remove_resource_ids);end;$$;
revoke all on function api.preview_booking_change(uuid,text,timestamptz,timestamptz,uuid[],uuid[]) from public,anon,authenticated;
grant execute on function api.preview_booking_change(uuid,text,timestamptz,timestamptz,uuid[],uuid[]) to authenticated;

create function internal.update_booking_for_actor(p jsonb,command_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare plan jsonb; ctx jsonb; item jsonb; anchor core.booking_bookings; created core.booking_bookings;
 groupid uuid; ids uuid[]; recipients uuid[]; notice uuid; requested uuid; previous core.booking_bookings; changed uuid[]:='{}';requests uuid[]:='{}';notifyrow record;
begin
 if jsonb_typeof(p->'expected_plan') is distinct from 'object' or jsonb_typeof(p->'add_resource_ids') is distinct from 'array'
 or jsonb_typeof(p->'remove_resource_ids') is distinct from 'array' then raise invalid_parameter_value using message='revision_required';end if;
 plan:=internal.preview_booking_change_for_actor((p->>'target_booking_id')::uuid,p->>'change_scope',
  (p->>'new_starts_at')::timestamptz,(p->>'new_ends_at')::timestamptz,array(select value::uuid from jsonb_array_elements_text(p->'add_resource_ids')),
  array(select value::uuid from jsonb_array_elements_text(p->'remove_resource_ids')));
 if jsonb_array_length(plan->'conflicts')>0 then raise check_violation using message='booking_change_conflicts';end if;
 if plan is distinct from p->'expected_plan' then raise sqlstate 'PT409' using message='stale_revision';end if;
 if (plan->>'change_count')::int=0 then raise invalid_parameter_value using message='booking_change_no_change';end if;
 -- Release only the reviewed removals before moving retained reservations.
 for ctx in select value from jsonb_array_elements(plan->'contexts') loop
  for item in select value from jsonb_array_elements(ctx->'remove') loop
   update core.booking_bookings set status='cancelled',revision=revision+1 where id=(item->>'id')::uuid;
  end loop;
 end loop;
 if jsonb_array_length(plan->'timing'->'events')>0 then
  for item in select value from jsonb_array_elements(plan->'timing'->'events') order by
   case when (value->>'starts_at')::timestamptz>=(value->>'old_starts_at')::timestamptz then (value->>'old_starts_at')::timestamptz end desc,
   (value->>'old_starts_at')::timestamptz,value->>'id' loop
   if (item->>'starts_at',item->>'ends_at') is not distinct from (item->>'old_starts_at',item->>'old_ends_at') then continue;end if;
   perform internal.revise_event_v2_for_actor((item->>'id')::uuid,'one',jsonb_build_object('starts_at',item->'starts_at','ends_at',item->'ends_at'),
    (item->>'revision')::bigint,md5('booking-change:'||command_id::text||':'||(item->>'id'))::uuid);
  end loop;
 else
  for item in select value from jsonb_array_elements(plan->'final_bookings') where value ? 'id' order by
   case when (value->>'starts_at')::timestamptz>=(value->>'old_starts_at')::timestamptz then (value->>'old_starts_at')::timestamptz end desc,
   (value->>'old_starts_at')::timestamptz,value->>'id' loop
   if (item->>'starts_at',item->>'ends_at') is not distinct from (item->>'old_starts_at',item->>'old_ends_at') then continue;end if;
   select * into previous from core.booking_bookings where id=(item->>'id')::uuid;
   update core.booking_bookings set starts_at=(item->>'starts_at')::timestamptz,ends_at=(item->>'ends_at')::timestamptz,status=item->>'status',revision=revision+1,
    decided_by=case when item->>'status'='pending' then null else decided_by end,decided_at=case when item->>'status'='pending' then null else decided_at end where id=previous.id;
   changed:=array_append(changed,previous.id);
   if previous.status='confirmed' and item->>'status'='pending' then requests:=array_append(requests,previous.id);end if;
  end loop;
  for notifyrow in select distinct on(coalesce(b.group_id,b.id),b.booked_by) b.* from core.booking_bookings b where b.id=any(changed) order by coalesce(b.group_id,b.id),b.booked_by,b.id loop
   perform internal.booking_notify(notifyrow.id,'rescheduled',array[notifyrow.booked_by]);end loop;
  for notifyrow in select distinct on(coalesce(b.group_id,b.id)) b.* from core.booking_bookings b where b.id=any(requests) order by coalesce(b.group_id,b.id),b.id loop
   perform internal.booking_notify(notifyrow.id,'requested',array(select profile_id from internal.booking_admin_profiles(notifyrow.organization_id)));end loop;
 end if;
 for ctx in select value from jsonb_array_elements(plan->'contexts') loop
  if jsonb_array_length(ctx->'add')+jsonb_array_length(ctx->'remove')=0 then continue;end if;
  select * into anchor from core.booking_bookings where id=(ctx->>'anchor_booking_id')::uuid;
  groupid:=anchor.group_id;notice:=null;requested:=null;
  select array_agg((value->>'id')::uuid) into ids from jsonb_array_elements(ctx->'existing');
  if jsonb_array_length(ctx->'add')>0 and groupid is null then
   groupid:=gen_random_uuid();update core.booking_bookings set group_id=groupid,revision=revision+1 where id=any(ids) and group_id is null;end if;
  select array_agg(distinct booked_by) into recipients from core.booking_bookings where id=any(ids);
  for item in select value from jsonb_array_elements(ctx->'add') loop
   insert into core.booking_bookings(organization_id,resource_id,starts_at,ends_at,title,notes,status,booked_by,team_id,event_id,group_id,series_id,series_sequence,decided_by,decided_at)
   values(anchor.organization_id,(item->>'resource_id')::uuid,(item->>'starts_at')::timestamptz,(item->>'ends_at')::timestamptz,
    anchor.title,anchor.notes,item->>'status',anchor.booked_by,anchor.team_id,anchor.event_id,groupid,anchor.series_id,anchor.series_sequence,
    case when item->>'status'='pending' then null else auth.uid() end,case when item->>'status'='pending' then null else now() end) returning * into created;
   notice:=created.id;if created.status='pending' then requested:=created.id;end if;
  end loop;
  perform internal.booking_notify(coalesce(notice,anchor.id),'resources_updated',recipients);
  -- A retained resource may already have requested reapproval during the time
  -- move. The group needs one request, covering all its pending resources.
  if requested is not null and not exists(select 1 from jsonb_array_elements(plan->'final_bookings') b
   where (b->>'id')::uuid=any(ids) and b->>'old_status'='confirmed' and b->>'status'='pending'
   and (b->>'starts_at',b->>'ends_at') is distinct from (b->>'old_starts_at',b->>'old_ends_at')) then
   perform internal.booking_notify(requested,'requested',array(select profile_id from internal.booking_admin_profiles(anchor.organization_id)));end if;
 end loop;
 return plan;
end;$$;
revoke all on function internal.update_booking_for_actor(jsonb,uuid) from public,anon,authenticated;
do $route$
declare definition text;marker text:='  case command_type';
begin
 definition:=pg_get_functiondef('internal.execute_booking_command_for_actor(uuid,text,jsonb,jsonb)'::regprocedure);
 if position(marker in definition)=0 then raise exception 'Booking executor contract missing';end if;
 execute replace(definition,marker,marker||E'\n    when ''update_booking'' then result := internal.update_booking_for_actor(p,command_id);');
end;$route$;
