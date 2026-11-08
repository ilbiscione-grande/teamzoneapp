-- Several resource reservations may share a stable series occurrence. Active
-- reservations remain unique per resource; cancelled history may be rebooked.
drop index core.booking_series_sequence_unique;
create unique index booking_series_active_resource_unique on core.booking_bookings(series_id,series_sequence,resource_id)
 where series_id is not null and status in ('pending','confirmed');
create index booking_series_occurrence on core.booking_bookings(series_id,series_sequence);
create or replace function internal.guard_booking_series_sequence() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' then
  if (new.series_id,new.series_sequence) is distinct from (old.series_id,old.series_sequence) then raise check_violation using message='immutable_series_sequence';end if;
 elsif new.series_id is not null then
  perform internal.lock_booking_organization(new.organization_id);
  if new.series_sequence is null then
   select coalesce(max(b.series_sequence),0)+1 into new.series_sequence from core.booking_bookings b where b.series_id=new.series_id;
  elsif new.group_id is null or not exists(select 1 from core.booking_bookings b where b.series_id=new.series_id
   and b.series_sequence=new.series_sequence and b.group_id=new.group_id and b.organization_id=new.organization_id) then
   raise check_violation using message='invalid_series_occurrence';end if;
 else new.series_sequence:=null;
 end if;
 return new;
end;$$;

create function internal.booking_resource_context(anchor core.booking_bookings) returns setof core.booking_bookings
language sql stable set search_path='' as $$
 select b.* from core.booking_bookings b where
 (anchor.series_id is not null and b.series_id=anchor.series_id and b.series_sequence=anchor.series_sequence)
 or (anchor.series_id is null and anchor.group_id is not null and b.group_id=anchor.group_id)
 or (anchor.series_id is null and anchor.group_id is null and b.id=anchor.id)
$$;
revoke all on function internal.booking_resource_context(core.booking_bookings) from public,anon,authenticated;

create function internal.preview_booking_resources_for_actor(target_booking_id uuid,change_scope text,add_resource_ids uuid[],remove_resource_ids uuid[])
returns jsonb language plpgsql security definer set search_path='' as $$
declare selected core.booking_bookings; activity core.events; occurrence core.events; anchor core.booking_bookings; booked core.booking_bookings;
 resource core.booking_resources; ids uuid[]:='{}'; event_ids uuid[]:='{}'; affected uuid[]:='{}'; all_resources uuid[]:='{}'; removed_ids uuid[]:='{}';
 additions uuid[]:=coalesce(add_resource_ids,'{}'); removals uuid[]:=coalesce(remove_resource_ids,'{}'); item uuid; matches integer;
 contexts jsonb:='[]'; unchanged jsonb:='[]'; events jsonb:='[]'; conflicts jsonb:='[]'; versions jsonb;
 existing jsonb; adding jsonb; removing jsonb; keeping jsonb; notes jsonb; history jsonb; snapshot jsonb; changes integer:=0;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 if change_scope is null or change_scope not in ('booking','series_forward','series_all','event_forward','event_all')
 or cardinality(additions)>10 or cardinality(removals)>10 or array_position(additions,null) is not null or array_position(removals,null) is not null
 or (select count(distinct x) from unnest(additions) x)<>cardinality(additions)
 or (select count(distinct x) from unnest(removals) x)<>cardinality(removals) or additions&&removals then raise invalid_parameter_value using message='invalid_resource_set';end if;
 select coalesce(array_agg(v order by v),'{}') into additions from unnest(additions) as vals(v);
 select coalesce(array_agg(v order by v),'{}') into removals from unnest(removals) as vals(v);
 select * into selected from core.booking_bookings where id=target_booking_id;
 if selected.id is null or internal.booking_actor_can_cancel(selected) is not true
 or (internal.booking_actor_role(selected.organization_id) is null and internal.booking_actor_leads_team(selected.organization_id,selected.team_id) is not true) then
  raise insufficient_privilege using message='not_allowed';end if;
 if selected.starts_at<=now() then raise invalid_parameter_value using message='resource_change_requires_future';end if;
 if change_scope in ('series_forward','series_all') then
  if selected.series_id is null or selected.event_id is not null then raise invalid_parameter_value using message='forward_series_not_found';end if;
  perform pg_advisory_xact_lock(hashtextextended('booking-series:'||selected.series_id::text,0));
 elsif selected.event_id is not null then
  select * into activity from core.events where id=selected.event_id;
  perform pg_advisory_xact_lock(hashtextextended('event-series:'||coalesce(activity.recurrence_id,selected.event_id)::text,0));
  select * into activity from core.events where id=selected.event_id for update;
  if activity.id is null or activity.archived_at is not null or activity.state not in ('draft','scheduled')
   or internal.actor_can_read_event(activity.id) is not true then raise insufficient_privilege using message='event_not_found';end if;
  if change_scope in ('event_forward','event_all') then
   if activity.recurrence_id is null then raise invalid_parameter_value using message='forward_series_not_found';end if;
   if activity.starts_at<=now() then raise invalid_parameter_value using message='resource_change_requires_future';end if;
   select array_agg(e.id order by e.occurrence_number,e.id) into event_ids from core.events e where e.recurrence_id=activity.recurrence_id
    and (change_scope='event_all' or e.occurrence_number>=activity.occurrence_number) and e.starts_at>now()
    and e.archived_at is null and e.state in ('draft','scheduled');
  else event_ids:=array[activity.id];end if;
  perform 1 from core.events e where e.id=any(event_ids) order by e.occurrence_number,e.id for update;
  if exists(select 1 from core.events e where e.id=any(event_ids) and internal.actor_can_read_event(e.id) is not true) then raise insufficient_privilege using message='event_not_found';end if;
 elsif change_scope<>'booking' then raise invalid_parameter_value using message='forward_series_not_found';
 end if;
 perform internal.lock_booking_organization(selected.organization_id);
 select * into selected from core.booking_bookings where id=target_booking_id for update;
 if internal.booking_actor_can_cancel(selected) is not true or selected.starts_at<=now() then raise insufficient_privilege using message='not_allowed';end if;
 if (select count(*) from core.booking_resources where id=any(additions||removals) and organization_id=selected.organization_id)
 <>cardinality(additions)+cardinality(removals) then raise insufficient_privilege using message='resource_change_not_found';end if;
 if change_scope='booking' then ids:=array[selected.id];
 elsif change_scope in ('series_forward','series_all') then
  select array_agg(b.id order by b.series_sequence,b.id) into ids from core.booking_bookings b where b.series_id=selected.series_id
   and b.resource_id=selected.resource_id and b.starts_at>now() and b.status in ('pending','confirmed')
   and (change_scope='series_all' or b.series_sequence>=selected.series_sequence);
  select coalesce(jsonb_agg(jsonb_build_object('series_sequence',q.series_sequence,'starts_at',q.starts_at,'reason','source_not_booked') order by q.series_sequence),'[]')
   into unchanged from (select b.series_sequence,min(b.starts_at) starts_at from core.booking_bookings b where b.series_id=selected.series_id
   and b.starts_at>now() and b.status in ('pending','confirmed') and (change_scope='series_all' or b.series_sequence>=selected.series_sequence)
   group by b.series_sequence having not bool_or(b.resource_id=selected.resource_id)) q;
 else
  for occurrence in select * from core.events where id=any(event_ids) order by occurrence_number,id loop
   select count(*) into matches from core.booking_bookings b where b.event_id=occurrence.id and b.resource_id=selected.resource_id
    and b.starts_at>now() and b.status in ('pending','confirmed');
   if matches>1 then raise invalid_parameter_value using message='resource_series_ambiguous';end if;
   if matches=1 then select b.id into item from core.booking_bookings b where b.event_id=occurrence.id and b.resource_id=selected.resource_id
    and b.starts_at>now() and b.status in ('pending','confirmed');ids:=array_append(ids,item);
   else unchanged:=unchanged||jsonb_build_array(jsonb_build_object('event_id',occurrence.id,'title',occurrence.title,'starts_at',occurrence.starts_at,'reason','source_not_booked'));end if;
  end loop;
 end if;
 ids:=coalesce(ids,'{}');
 if not(selected.id=any(ids)) then raise sqlstate 'PT409' using message='stale_revision';end if;
 select coalesce(array_agg(distinct c.id),'{}') into affected from core.booking_bookings b cross join lateral internal.booking_resource_context(b) c where b.id=any(ids);
 perform 1 from core.booking_bookings where id=any(affected) order by id for update;
 if exists(select 1 from core.booking_bookings b where b.id=any(affected) and
  (b.organization_id<>selected.organization_id or (b.status in ('pending','confirmed') and b.ends_at>now() and internal.booking_actor_can_cancel(b) is not true))) then
  raise insufficient_privilege using message='not_allowed';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'revision',e.revision,'starts_at',e.starts_at,'ends_at',e.ends_at,'title',e.title) order by e.occurrence_number,e.id),'[]')
  into events from core.events e where e.id=any(event_ids);
 all_resources:=additions||removals;
 for anchor in select * from core.booking_bookings where id=any(ids) order by starts_at,id loop
  if anchor.team_id is not null and internal.booking_actor_can_book_team(anchor.organization_id,anchor.team_id) is not true then raise insufficient_privilege using message='not_team_leader';end if;
  if exists(select 1 from internal.booking_resource_context(anchor) b where b.event_id is distinct from anchor.event_id) then raise invalid_parameter_value using message='invalid_resource_set';end if;
  existing:='[]';adding:='[]';removing:='[]';keeping:='[]';notes:='[]';
  for booked in select * from internal.booking_resource_context(anchor) where status in ('pending','confirmed') order by resource_id,id loop
   select * into resource from core.booking_resources where id=booked.resource_id;
   snapshot:=to_jsonb(booked)||jsonb_build_object('resource_name',resource.name);
   existing:=existing||jsonb_build_array(snapshot);all_resources:=array_append(all_resources,resource.id);
   if resource.id=any(removals) then
    removing:=removing||jsonb_build_array(snapshot);removed_ids:=array_append(removed_ids,booked.id);
    if booked.starts_at<=now() then conflicts:=conflicts||jsonb_build_array(jsonb_build_object('resource_name',resource.name,'starts_at',booked.starts_at,'reason','resource_change_requires_future'));end if;
   else keeping:=keeping||jsonb_build_array(snapshot);end if;
  end loop;
  foreach item in array additions loop
   select * into resource from core.booking_resources where id=item;
   if exists(select 1 from jsonb_array_elements(existing) b where b->>'resource_id'=item::text) then
    notes:=notes||jsonb_build_array(jsonb_build_object('resource_name',resource.name,'reason','already_booked'));continue;end if;
   select jsonb_agg(jsonb_build_object('id',b.id,'revision',b.revision,'status',b.status) order by b.id) into history
    from internal.booking_resource_context(anchor) b where b.resource_id=item and b.status in ('cancelled','declined');
   if change_scope<>'booking' and history is not null then
    notes:=notes||jsonb_build_array(jsonb_build_object('resource_name',resource.name,'reason','previously_cancelled','history',history));continue;end if;
   adding:=adding||jsonb_build_array(jsonb_build_object('resource_id',resource.id,'resource_name',resource.name,'starts_at',anchor.starts_at,'ends_at',anchor.ends_at,
    'status',case when resource.requires_approval and internal.booking_actor_role(anchor.organization_id) is distinct from 'admin' then 'pending' else 'confirmed' end));
   if not resource.active then conflicts:=conflicts||jsonb_build_array(jsonb_build_object('resource_name',resource.name,'starts_at',anchor.starts_at,'reason','resource_inactive'));end if;
   if not internal.booking_within_disposition(resource,anchor.starts_at,anchor.ends_at) then conflicts:=conflicts||jsonb_build_array(jsonb_build_object('resource_name',resource.name,'starts_at',anchor.starts_at,'reason','resource_outside_disposition'));end if;
  end loop;
  if jsonb_array_length(keeping)+jsonb_array_length(adding)>10 then raise invalid_parameter_value using message='too_many_resources';end if;
  changes:=changes+jsonb_array_length(adding)+jsonb_array_length(removing);
  contexts:=contexts||jsonb_build_array(jsonb_build_object('anchor_booking_id',anchor.id,'group_id',anchor.group_id,'series_id',anchor.series_id,
   'series_sequence',anchor.series_sequence,'event_id',anchor.event_id,'starts_at',anchor.starts_at,'ends_at',anchor.ends_at,
   'existing',existing,'add',adding,'remove',removing,'keep',keeping,'unchanged_resources',notes));
 end loop;
 -- Compare additions with the final state, excluding all planned removals.
 select conflicts||coalesce(jsonb_agg(distinct jsonb_build_object('resource_name',n->>'resource_name','starts_at',n->'starts_at','reason','resource_busy')),'[]') into conflicts
 from jsonb_array_elements(contexts) c cross join lateral jsonb_array_elements(c->'add') n
 where exists(select 1 from core.booking_bookings b where b.organization_id=selected.organization_id and b.status in ('pending','confirmed')
  and not(b.id=any(removed_ids)) and b.starts_at<(n->>'ends_at')::timestamptz and b.ends_at>(n->>'starts_at')::timestamptz
  and internal.booking_resources_overlap(b.resource_id,(n->>'resource_id')::uuid));
 select conflicts||coalesce(jsonb_agg(distinct jsonb_build_object('resource_name',a->>'resource_name','starts_at',a->'starts_at','reason','resource_busy')),'[]') into conflicts
 from jsonb_array_elements(contexts) c cross join lateral jsonb_array_elements(c->'add') a
 cross join jsonb_array_elements(contexts) d cross join lateral jsonb_array_elements(d->'add') b
 where (c->>'anchor_booking_id',a->>'resource_id')<(d->>'anchor_booking_id',b->>'resource_id')
 and (a->>'starts_at')::timestamptz<(b->>'ends_at')::timestamptz and (a->>'ends_at')::timestamptz>(b->>'starts_at')::timestamptz
 and internal.booking_resources_overlap((a->>'resource_id')::uuid,(b->>'resource_id')::uuid);
 select jsonb_object_agg(r.id::text,r.revision) into versions from core.booking_resources r where r.id in
  (select a.id from unnest(all_resources) as resids(resource_id) cross join lateral internal.booking_resource_ancestors(resids.resource_id) a);
 return jsonb_build_object('target_booking_id',selected.id,'scope',change_scope,'source_resource_id',selected.resource_id,
  'add_resource_ids',to_jsonb(array(select x from unnest(additions) x order by x)),'remove_resource_ids',to_jsonb(array(select x from unnest(removals) x order by x)),
  'contexts',contexts,'unchanged_contexts',unchanged,'events',events,'resources',versions,'conflicts',conflicts,'change_count',changes);
end;$$;
revoke all on function internal.preview_booking_resources_for_actor(uuid,text,uuid[],uuid[]) from public,anon,authenticated;

create function api.preview_booking_resources(target_booking_id uuid,change_scope text,add_resource_ids uuid[],remove_resource_ids uuid[]) returns jsonb
language plpgsql security definer set search_path='' as $$
begin return internal.preview_booking_resources_for_actor(target_booking_id,change_scope,add_resource_ids,remove_resource_ids);end;$$;
revoke all on function api.preview_booking_resources(uuid,text,uuid[],uuid[]) from public,anon,authenticated;
grant execute on function api.preview_booking_resources(uuid,text,uuid[],uuid[]) to authenticated;

create function internal.update_booking_resources_for_actor(p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare plan jsonb; ctx jsonb; item jsonb; anchor core.booking_bookings; created core.booking_bookings; groupid uuid;
 notice uuid; requested uuid; recipients uuid[]; ids uuid[];
begin
 if jsonb_typeof(p->'expected_plan') is distinct from 'object' or jsonb_typeof(p->'add_resource_ids') is distinct from 'array'
 or jsonb_typeof(p->'remove_resource_ids') is distinct from 'array' then raise invalid_parameter_value using message='revision_required';end if;
 plan:=internal.preview_booking_resources_for_actor((p->>'target_booking_id')::uuid,p->>'change_scope',
  array(select value::uuid from jsonb_array_elements_text(p->'add_resource_ids')),array(select value::uuid from jsonb_array_elements_text(p->'remove_resource_ids')));
 if jsonb_array_length(plan->'conflicts')>0 then raise check_violation using message='resource_set_conflicts';end if;
 if plan is distinct from p->'expected_plan' then raise sqlstate 'PT409' using message='stale_revision';end if;
 if (plan->>'change_count')::int=0 then raise invalid_parameter_value using message='resource_set_no_change';end if;
 -- Remove first across the whole scope, then claim additions. Every step is
 -- inside this command's transaction; failures roll all changes back.
 for ctx in select value from jsonb_array_elements(plan->'contexts') loop
  for item in select value from jsonb_array_elements(ctx->'remove') loop
   update core.booking_bookings set status='cancelled',revision=revision+1 where id=(item->>'id')::uuid;
  end loop;
 end loop;
 for ctx in select value from jsonb_array_elements(plan->'contexts') loop
  if jsonb_array_length(ctx->'add')+jsonb_array_length(ctx->'remove')=0 then continue;end if;
  select * into anchor from core.booking_bookings where id=(ctx->>'anchor_booking_id')::uuid;
  groupid:=anchor.group_id;notice:=null;requested:=null;
  select array_agg((value->>'id')::uuid) into ids from jsonb_array_elements(ctx->'existing');
  if jsonb_array_length(ctx->'add')>0 and groupid is null then
   groupid:=gen_random_uuid();update core.booking_bookings set group_id=groupid,revision=revision+1 where id=any(ids) and group_id is null;
  end if;
  select array_agg(distinct booked_by) into recipients from core.booking_bookings where id=any(ids);
  for item in select value from jsonb_array_elements(ctx->'add') loop
   insert into core.booking_bookings(organization_id,resource_id,starts_at,ends_at,title,notes,status,booked_by,team_id,event_id,group_id,series_id,series_sequence,decided_by,decided_at)
   values(anchor.organization_id,(item->>'resource_id')::uuid,(item->>'starts_at')::timestamptz,(item->>'ends_at')::timestamptz,
    anchor.title,anchor.notes,item->>'status',anchor.booked_by,anchor.team_id,anchor.event_id,groupid,anchor.series_id,anchor.series_sequence,
    case when item->>'status'='pending' then null else auth.uid() end,case when item->>'status'='pending' then null else now() end) returning * into created;
   notice:=created.id;if created.status='pending' then requested:=created.id;end if;
  end loop;
  notice:=coalesce(notice,anchor.id);
  perform internal.booking_notify(notice,'resources_updated',recipients);
  if requested is not null then perform internal.booking_notify(requested,'requested',array(select profile_id from internal.booking_admin_profiles(anchor.organization_id)));end if;
 end loop;
 return plan;
end;$$;
revoke all on function internal.update_booking_resources_for_actor(jsonb) from public,anon,authenticated;

do $route$
declare definition text; marker text; patched text;
begin
 definition:=pg_get_functiondef('internal.execute_booking_command_for_actor(uuid,text,jsonb,jsonb)'::regprocedure);marker:='  case command_type';
 if position(marker in definition)=0 then raise exception 'Booking command route missing';end if;
 execute replace(definition,marker,marker||E'\n    when ''update_booking_resources'' then result := internal.update_booking_resources_for_actor(p);');
 definition:=pg_get_functiondef('internal.booking_json(core.booking_bookings,text)'::regprocedure);
 patched:=replace(definition,'select count(*) from core.booking_bookings b where b.series_id=booking.series_id','select count(distinct b.series_sequence) from core.booking_bookings b where b.series_id=booking.series_id');
 patched:=replace(patched,'select count(*) from core.booking_bookings other','select count(distinct other.series_sequence) from core.booking_bookings other');
 if patched=definition then raise exception 'Series count contract missing';end if;execute patched;
 definition:=replace(pg_get_functiondef('internal.preview_booking_resource_for_actor(uuid,uuid)'::regprocedure),E'\r\n',E'\n');
 marker:=E'and b.starts_at<booked.ends_at and b.ends_at>booked.starts_at\n  and internal.booking_resources_overlap(destination.id,b.resource_id)';
 if position(marker in definition)=0 then raise exception 'Single swap conflict contract missing';end if;
 execute replace(definition,marker,'and ((b.starts_at<booked.ends_at and b.ends_at>booked.starts_at and internal.booking_resources_overlap(destination.id,b.resource_id)) or (b.series_id=booked.series_id and b.series_sequence=booked.series_sequence and b.resource_id=destination.id))');
end;$route$;

alter table core.booking_notifications drop constraint booking_notifications_kind_check;
alter table core.booking_notifications add constraint booking_notifications_kind_check
 check(kind in ('requested','approved','declined','cancelled','rescheduled','resource_changed','resources_updated'));
do $notification$
declare definition text; patched text;
begin
 definition:=pg_get_functiondef('internal.push_message_for_outbox(uuid)'::regprocedure);
 patched:=replace(definition,'when ''booking.requested.v1'' then',
  'when ''booking.resources_updated.v1'' then case when swedish then U&''Bokningens resurser har \00e4ndrats'' else ''Booking resources updated'' end
   when ''booking.requested.v1'' then');
 if patched=definition then raise exception 'Push formatter missing';end if;execute patched;
 definition:=pg_get_functiondef('internal.notification_title(text)'::regprocedure);
 patched:=replace(definition,'when event_type = ''booking.requested.v1'' then',
  'when event_type = ''booking.resources_updated.v1'' then U&''Bokningens resurser har \00e4ndrats''
   when event_type = ''booking.requested.v1'' then');
 if patched=definition then raise exception 'Notification title missing';end if;execute patched;
 definition:=pg_get_functiondef('internal.notification_preview(text)'::regprocedure);
 patched:=replace(definition,'when event_type = ''booking.requested.v1'' then',
  'when event_type = ''booking.resources_updated.v1'' then U&''Resurser har lagts till eller tagits bort. Se bokningen i Bokningshanteraren.''
   when event_type = ''booking.requested.v1'' then');
 if patched=definition then raise exception 'Notification preview missing';end if;execute patched;
end;$notification$;
