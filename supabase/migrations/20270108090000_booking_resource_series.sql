-- Reuse the single-booking replacement rules after locking the complete scope.
-- Existing resource exceptions are explicit unchanged rows, never overwritten.
create function internal.preview_booking_resource_series_for_actor(target_booking_id uuid,new_resource_id uuid,change_scope text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare anchor core.booking_bookings; activity core.events; occurrence core.events; booked core.booking_bookings;
 ids uuid[]:='{}'; event_ids uuid[]:='{}'; candidate_ids uuid[]:='{}'; org uuid; plans jsonb:='[]'; unchanged jsonb:='[]'; events jsonb:='[]';
 plan jsonb; conflicts jsonb:='[]'; matches integer;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 if change_scope is null or change_scope not in ('series_forward','series_all','event_forward','event_all') then raise invalid_parameter_value using message='invalid_command';end if;
 select * into anchor from core.booking_bookings where id=target_booking_id;
 if anchor.id is null or internal.booking_actor_can_cancel(anchor) is not true
  or (internal.booking_actor_role(anchor.organization_id) is null and internal.booking_actor_leads_team(anchor.organization_id,anchor.team_id) is not true) then
  raise insufficient_privilege using message='not_allowed';end if;
 if anchor.starts_at<=now() then raise invalid_parameter_value using message='resource_change_requires_future';end if;
 if change_scope in ('series_forward','series_all') then
  if anchor.series_id is null or anchor.event_id is not null then raise invalid_parameter_value using message='forward_series_not_found';end if;
  perform pg_advisory_xact_lock(hashtextextended('booking-series:'||anchor.series_id::text,0));
 else
  select * into activity from core.events where id=anchor.event_id;
  if activity.id is null or activity.recurrence_id is null then raise invalid_parameter_value using message='forward_series_not_found';end if;
  perform pg_advisory_xact_lock(hashtextextended('event-series:'||activity.recurrence_id::text,0));
  select * into activity from core.events where id=anchor.event_id for update;
  if activity.starts_at<=now() or activity.archived_at is not null or activity.state not in ('draft','scheduled') then
   raise invalid_parameter_value using message='resource_change_requires_future';end if;
  select array_agg(e.id order by e.occurrence_number,e.id) into event_ids from core.events e
   where e.recurrence_id=activity.recurrence_id and (change_scope='event_all' or e.occurrence_number>=activity.occurrence_number)
    and e.starts_at>now() and e.archived_at is null and e.state in ('draft','scheduled');
  perform 1 from core.events e where e.id=any(event_ids) order by e.occurrence_number,e.id for update;
  if exists(select 1 from core.events e where e.id=any(event_ids) and internal.actor_can_read_event(e.id) is not true) then
   raise insufficient_privilege using message='event_not_found';end if;
 end if;
 -- Keep organisation-before-booking order shared with all reservation writers.
 perform internal.lock_booking_organization(anchor.organization_id);
 select * into anchor from core.booking_bookings where id=target_booking_id for update;
 if internal.booking_actor_can_cancel(anchor) is not true or anchor.starts_at<=now() then raise insufficient_privilege using message='not_allowed';end if;
 if change_scope in ('series_forward','series_all') then
  select array_agg(b.id order by b.id) into candidate_ids from core.booking_bookings b where b.series_id=anchor.series_id
   and (change_scope='series_all' or b.series_sequence>=anchor.series_sequence) and b.starts_at>now() and b.status in ('pending','confirmed');
  perform 1 from core.booking_bookings b where b.id=any(candidate_ids) order by b.id for update;
  for booked in select * from core.booking_bookings b where b.id=any(candidate_ids) order by b.series_sequence,b.id loop
   if booked.organization_id<>anchor.organization_id or booked.event_id is not null then raise insufficient_privilege using message='not_allowed';end if;
   if booked.resource_id=anchor.resource_id then ids:=array_append(ids,booked.id);
   else unchanged:=unchanged||jsonb_build_array(jsonb_build_object('id',booked.id,'revision',booked.revision,'series_sequence',booked.series_sequence,
    'starts_at',booked.starts_at,'ends_at',booked.ends_at,'resource_id',booked.resource_id,
    'resource_name',(select name from core.booking_resources where id=booked.resource_id),'reason','different_resource'));end if;
  end loop;
 else
  for occurrence in select * from core.events e where e.id=any(event_ids) order by e.occurrence_number,e.id loop
   events:=events||jsonb_build_array(jsonb_build_object('id',occurrence.id,'revision',occurrence.revision,'title',occurrence.title,
    'starts_at',occurrence.starts_at,'ends_at',occurrence.ends_at,'occurrence_number',occurrence.occurrence_number));
   select count(*) into matches from core.booking_bookings b where b.event_id=occurrence.id and b.resource_id=anchor.resource_id
    and b.starts_at>now() and b.status in ('pending','confirmed');
   if matches>1 then raise invalid_parameter_value using message='resource_series_ambiguous';end if;
   if matches=1 then
    select id into org from core.booking_bookings b where b.event_id=occurrence.id and b.resource_id=anchor.resource_id
     and b.starts_at>now() and b.status in ('pending','confirmed');
    ids:=array_append(ids,org);
   else unchanged:=unchanged||jsonb_build_array(jsonb_build_object('event_id',occurrence.id,'title',occurrence.title,
    'starts_at',occurrence.starts_at,'ends_at',occurrence.ends_at,'reason','resource_not_booked'));end if;
  end loop;
  perform 1 from core.booking_bookings b where b.id=any(ids) order by b.id for update;
 end if;
 if not(anchor.id=any(ids)) then raise sqlstate 'PT409' using message='stale_revision';end if;
 for booked in select * from core.booking_bookings b where b.id=any(ids) order by b.starts_at,b.id loop
  plan:=internal.preview_booking_resource_for_actor(booked.id,new_resource_id);
  plans:=plans||jsonb_build_array(plan);
  select conflicts||coalesce(jsonb_agg(jsonb_build_object('booking_id',booked.id,'resource_name',plan->>'new_resource_name',
   'starts_at',booked.starts_at,'reason',reason)),'[]'::jsonb) into conflicts from jsonb_array_elements_text(plan->'conflicts') as reasons(reason);
 end loop;
 return jsonb_build_object('target_booking_id',anchor.id,'new_resource_id',new_resource_id,'source_resource_id',anchor.resource_id,
  'source_resource_name',(select name from core.booking_resources where id=anchor.resource_id),'scope',change_scope,
  'series_id',anchor.series_id,'series_sequence',anchor.series_sequence,'recurrence_id',activity.recurrence_id,
  'events',events,'bookings',plans,'unchanged',unchanged,'conflicts',conflicts);
end;$$;
revoke all on function internal.preview_booking_resource_series_for_actor(uuid,uuid,text) from public,anon,authenticated;

create function api.preview_booking_resource_series(target_booking_id uuid,new_resource_id uuid,change_scope text) returns jsonb
language plpgsql security definer set search_path='' as $$
begin return internal.preview_booking_resource_series_for_actor(target_booking_id,new_resource_id,change_scope);end;$$;
revoke all on function api.preview_booking_resource_series(uuid,uuid,text) from public,anon,authenticated;
grant execute on function api.preview_booking_resource_series(uuid,uuid,text) to authenticated;

create function internal.change_booking_resource_series_for_actor(p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare plan jsonb; item jsonb;
begin
 if jsonb_typeof(p->'expected_plan') is distinct from 'object' then raise invalid_parameter_value using message='revision_required';end if;
 begin
  plan:=internal.preview_booking_resource_series_for_actor((p->>'target_booking_id')::uuid,(p->>'new_resource_id')::uuid,p->>'change_scope');
 exception when invalid_parameter_value then
  if sqlerrm='resource_change_same' then raise sqlstate 'PT409' using message='stale_revision';end if;
  raise;
 end;
 if jsonb_array_length(plan->'conflicts')>0 then raise check_violation using message='resource_change_conflicts';end if;
 if plan is distinct from p->'expected_plan' then raise sqlstate 'PT409' using message='stale_revision';end if;
 for item in select value from jsonb_array_elements(plan->'bookings') loop
  perform internal.change_booking_resource_for_actor(jsonb_build_object('target_booking_id',item->'target_booking_id',
   'new_resource_id',item->'new_resource_id','expected_plan',item));
 end loop;
 return plan;
end;$$;
revoke all on function internal.change_booking_resource_series_for_actor(jsonb) from public,anon,authenticated;

do $route$
declare definition text; marker text:=E'begin\n';
begin
 definition:=replace(pg_get_functiondef('internal.change_booking_resource_for_actor(jsonb)'::regprocedure),E'\r\n',E'\n');
 if position(marker in definition)=0 then raise exception 'Resource swap route missing';end if;
 execute replace(definition,marker,marker||E' if p ? ''change_scope'' then\n  if p->>''change_scope'' is null or p->>''change_scope'' not in (''booking'',''series_forward'',''series_all'',''event_forward'',''event_all'') then raise invalid_parameter_value using message=''invalid_command'';end if;\n  if p->>''change_scope''<>''booking'' then return internal.change_booking_resource_series_for_actor(p);end if;\n end if;\n');
 definition:=pg_get_functiondef('internal.booking_json(core.booking_bookings,text)'::regprocedure);
 marker:='''event_id'', booking.event_id,';
 if position(marker in definition)=0 then raise exception 'Booking JSON route missing';end if;
 execute replace(definition,marker,marker||E'\n ''resource_event_series'',exists(select 1 from core.events e where e.id=booking.event_id and e.recurrence_id is not null and internal.actor_can_read_event(e.id)),');
end;$route$;
