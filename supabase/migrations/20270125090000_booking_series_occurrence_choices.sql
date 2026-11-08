-- All selected resources are reserved together for each accepted occurrence.
create or replace function internal.create_booking_multi_series_for_actor(p jsonb, preview boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare ids uuid[];org uuid;anchor core.booking_resources;res core.booking_resources;actor_role text;
 base jsonb;slot jsonb;check_result jsonb;times jsonb:='[]';plan jsonb;versions jsonb;
 clash boolean;outside boolean;state text:='confirmed';sid uuid;gid uuid;row core.booking_bookings;seq integer;
 slot_ids uuid[];all_ids uuid[];override jsonb;changes jsonb:=coalesce(p->'occurrence_overrides','[]'::jsonb);
 original_start timestamptz;actual_start timestamptz;actual_end timestamptz;
 created integer:=0;first_pending uuid;first_booking uuid;days smallint[];
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 if jsonb_typeof(p->'target_resource_ids') is distinct from 'array' then raise invalid_parameter_value using message='invalid_resources';end if;
 select array_agg(value::uuid order by value) into ids from jsonb_array_elements_text(p->'target_resource_ids');
 if cardinality(ids) is null or cardinality(ids) not between 1 and 10 or array_position(ids,null) is not null
 or (select count(distinct x) from unnest(ids) x)<>cardinality(ids) then raise invalid_parameter_value using message='invalid_resources';end if;
 select * into anchor from core.booking_resources where id=ids[1];org:=anchor.organization_id;
 perform internal.lock_booking_organization(org);
 actor_role:=internal.booking_actor_role(org);
 if actor_role is null then raise insufficient_privilege using message='not_found';end if;
 if (select count(*) from core.booking_resources where id=any(ids) and organization_id=org)<>cardinality(ids) then raise invalid_parameter_value using message='invalid_resources';end if;
 if exists(select 1 from core.booking_resources where id=any(ids) and not active) then raise invalid_parameter_value using message='resource_inactive';end if;
 if exists(select 1 from unnest(ids) a cross join unnest(ids) b where a<b and internal.booking_resources_overlap(a,b)) then raise invalid_parameter_value using message='invalid_resources';end if;
 if jsonb_typeof(p->'series_weekdays') is distinct from 'array' or p->>'series_interval' is null or p->>'first_day' is null
 or p->>'last_day' is null or p->>'start_at' is null or p->>'end_at' is null or p->>'zone' is null then raise invalid_parameter_value using message='invalid_series';end if;
 select array_agg(value::smallint) into days from jsonb_array_elements_text(p->'series_weekdays');
 base:=internal.create_booking_series_for_actor(ids[1],days,(p->>'series_interval')::smallint,(p->>'first_day')::date,(p->>'last_day')::date,
 (p->>'start_at')::time,(p->>'end_at')::time,p->>'zone',p->>'booking_title',p->>'booking_notes',(p->>'target_team_id')::uuid,true);
 if jsonb_array_length(base->'times')=0 then raise invalid_parameter_value using message='in_the_past';end if;
 if jsonb_typeof(changes) is distinct from 'array' or jsonb_array_length(changes)>200 then raise invalid_parameter_value using message='invalid_series';end if;
 if exists(select 1 from jsonb_array_elements(changes) x group by (x->>'original_starts_at')::timestamptz having count(*)>1)
 or exists(select 1 from jsonb_array_elements(changes) x where not exists(select 1 from jsonb_array_elements(base->'times') t where (t->>'starts_at')::timestamptz=(x->>'original_starts_at')::timestamptz))
 then raise invalid_parameter_value using message='invalid_series';end if;
 all_ids:=ids;
 if actor_role<>'admin' and exists(select 1 from core.booking_resources where id=any(ids) and requires_approval) then state:='pending';end if;
 for slot in select value from jsonb_array_elements(base->'times') loop
  original_start:=(slot->>'starts_at')::timestamptz;
  select value into override from jsonb_array_elements(changes) where (value->>'original_starts_at')::timestamptz=original_start;
  slot_ids:=ids;actual_start:=original_start;actual_end:=(slot->>'ends_at')::timestamptz;
  if override is not null then
   if jsonb_typeof(override->'resource_ids') is distinct from 'array' then raise invalid_parameter_value using message='invalid_resources';end if;
   select array_agg(value::uuid order by value) into slot_ids from jsonb_array_elements_text(override->'resource_ids');
   actual_start:=(override->>'starts_at')::timestamptz;actual_end:=(override->>'ends_at')::timestamptz;
   -- An exception changes only this date, and preserves its duration. Distinct series dates cannot overlap.
   if actual_start is null or actual_end is null or actual_end-actual_start<>((slot->>'ends_at')::timestamptz-original_start)
    or (actual_start at time zone (p->>'zone'))::date<>(original_start at time zone (p->>'zone'))::date
    or (actual_end at time zone (p->>'zone'))::date<>(original_start at time zone (p->>'zone'))::date
   then raise invalid_parameter_value using message='invalid_time';end if;
  end if;
  if cardinality(slot_ids) is null or cardinality(slot_ids) not between 1 and 10 or array_position(slot_ids,null) is not null
   or (select count(distinct x) from unnest(slot_ids) x)<>cardinality(slot_ids)
   or (select count(*) from core.booking_resources where id=any(slot_ids) and organization_id=org and active)<>cardinality(slot_ids)
   or exists(select 1 from unnest(slot_ids) a cross join unnest(slot_ids) z where a<z and internal.booking_resources_overlap(a,z))
  then raise invalid_parameter_value using message='invalid_resources';end if;
  all_ids:=all_ids||slot_ids;
  if actor_role<>'admin' and exists(select 1 from core.booking_resources where id=any(slot_ids) and requires_approval) then state:='pending';end if;
  check_result:=internal.create_booking_group_for_actor(slot_ids,actual_start,actual_end,
    p->>'booking_title',p->>'booking_notes',(p->>'target_team_id')::uuid,null,true);
  select bool_or((x->>'busy')::boolean) into clash from jsonb_array_elements(check_result->'items') x;
  select bool_or(not internal.booking_within_disposition(r,actual_start,actual_end)) into outside from core.booking_resources r where id=any(slot_ids);
  times:=times||jsonb_build_array(jsonb_build_object('original_starts_at',original_start,'starts_at',actual_start,'ends_at',actual_end,
   'resource_ids',to_jsonb(slot_ids),'clash',clash,'outside_disposition',outside,'changed',override is not null,
   'blocked_resources',(select coalesce(jsonb_agg(jsonb_build_object('resource_id',r.id,'name',r.name,
    'outside_disposition',not internal.booking_within_disposition(r,actual_start,actual_end)) order by r.id),'[]'::jsonb)
    from core.booking_resources r where r.id=any(slot_ids) and exists(select 1 from jsonb_array_elements(check_result->'items') x where x->>'resource_id'=r.id::text and (x->>'busy')::boolean))));
 end loop;
 select jsonb_object_agg(r.id::text,r.revision) into versions from core.booking_resources r where r.id in
 (select a.id from unnest(all_ids) x cross join lateral internal.booking_resource_ancestors(x) a);
 plan:=jsonb_build_object('series_id',null,'status',state,'created',0,'times',times,'resource_revisions',versions);
 if preview then return plan;end if;
 if jsonb_typeof(p->'expected_plan') is distinct from 'object' then raise invalid_parameter_value using message='revision_required';end if;
 if plan is distinct from p->'expected_plan' then raise sqlstate 'PT409' using message='stale_revision';end if;
 if not exists(select 1 from jsonb_array_elements(times) x where not (x->>'clash')::boolean) then raise exclusion_violation using message='resource_busy';end if;
 insert into core.booking_series(organization_id,resource_id,booked_by,team_id,title,notes,weekdays,interval_weeks,starts_on,ends_on,start_time,end_time,timezone)
 values(org,ids[1],auth.uid(),(p->>'target_team_id')::uuid,nullif(btrim(p->>'booking_title'),''),nullif(btrim(p->>'booking_notes'),''),days,
 (p->>'series_interval')::smallint,(p->>'first_day')::date,(p->>'last_day')::date,(p->>'start_at')::time,(p->>'end_at')::time,p->>'zone') returning id into sid;
 for slot in select value from jsonb_array_elements(times) loop
  if (slot->>'clash')::boolean then continue;end if;
  gid:=gen_random_uuid();seq:=null;
  select array_agg(value::uuid) into slot_ids from jsonb_array_elements_text(slot->'resource_ids');
  for res in select * from core.booking_resources where id=any(slot_ids) order by id loop
   insert into core.booking_bookings(organization_id,resource_id,starts_at,ends_at,title,notes,status,booked_by,team_id,group_id,series_id,series_sequence,decided_by,decided_at)
   values(org,res.id,(slot->>'starts_at')::timestamptz,(slot->>'ends_at')::timestamptz,nullif(btrim(p->>'booking_title'),''),nullif(btrim(p->>'booking_notes'),''),state,
   auth.uid(),(p->>'target_team_id')::uuid,gid,sid,seq,case when state='confirmed' then auth.uid() end,case when state='confirmed' then now() end) returning * into row;
   seq:=row.series_sequence;first_booking:=coalesce(first_booking,row.id);
   if state='pending' then first_pending:=coalesce(first_pending,row.id);end if;
  end loop;
  created:=created+1;
 end loop;
 if first_pending is not null then perform internal.booking_notify(first_pending,'requested',array(select profile_id from internal.booking_admin_profiles(org)));end if;
 return plan||jsonb_build_object('series_id',sid,'created',created,'anchor_booking_id',first_booking);
end;$$;
revoke all on function internal.create_booking_multi_series_for_actor(jsonb,boolean) from public,anon,authenticated;
