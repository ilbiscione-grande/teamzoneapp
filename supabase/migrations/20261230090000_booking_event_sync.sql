-- Activity -> booking synchronization. Existing event APIs keep their
-- authorization, revisions, retry ledger, event history and outbox transaction.
create function internal.guard_booking_event_link() returns trigger
language plpgsql security definer set search_path = '' as $$
declare event_row core.events; attached boolean;
begin
 if new.event_id is null or new.status not in ('pending','confirmed') then return new;end if;
 attached:=tg_op='INSERT';
 if tg_op='UPDATE' then attached:=new.event_id is distinct from old.event_id or old.status not in ('pending','confirmed');end if;
 -- Creators lock the event before organisation/resource locks. This also
 -- protects privileged direct inserts from racing cancellation or rescheduling.
 if attached or (tg_op='UPDATE' and (new.starts_at,new.ends_at) is distinct from (old.starts_at,old.ends_at)) then
  select * into event_row from core.events where id=new.event_id for update;
 else select * into event_row from core.events where id=new.event_id;end if;
 if event_row.id is null or event_row.archived_at is not null or event_row.state='cancelled'
   or (attached and event_row.state not in ('draft','scheduled'))
   or not exists(select 1 from core.booking_organizations o where o.id=new.organization_id and o.teamzone_club_id=event_row.club_id)
   or not exists(select 1 from core.event_teams t where t.event_id=new.event_id and t.team_id=new.team_id) then
   raise check_violation using message='event_not_found';end if;
 return new;
end; $$;
revoke all on function internal.guard_booking_event_link() from public,anon,authenticated;
create trigger booking_000_event_link before insert or update of event_id,starts_at,ends_at,status on core.booking_bookings
 for each row execute function internal.guard_booking_event_link();

create function internal.sync_bookings_from_event() returns trigger
language plpgsql security definer set search_path = '' as $$
declare org uuid; booking core.booking_bookings; resource core.booking_resources;
 cancel_bookings boolean; new_start timestamptz; new_end timestamptz; changed_ids uuid[]:='{}'::uuid[];
 request_ids uuid[]:='{}'::uuid[]; notice record; previous_status text;
begin
 cancel_bookings:=tg_op='DELETE';
 if tg_op<>'DELETE' then
  cancel_bookings:=new.state='cancelled' or new.archived_at is not null;
  if not cancel_bookings and (new.starts_at,new.ends_at) is not distinct from (old.starts_at,old.ends_at) then return new;end if;
 end if;
 -- Reserve all affected organisations in a deterministic order before rows.
 for org in select distinct b.organization_id from core.booking_bookings b
   where b.event_id=old.id and b.status in ('pending','confirmed') and b.ends_at>now() order by b.organization_id loop
  perform internal.lock_booking_organization(org);
 end loop;
 perform 1 from core.booking_bookings b where b.event_id=old.id and b.status in ('pending','confirmed') and b.ends_at>now() order by b.id for update;
 -- Moving later: latest slot first. Moving earlier: earliest first. This avoids
 -- transient collisions with another slot linked to this same activity.
 for booking in select b.* from core.booking_bookings b
   where b.event_id=old.id and b.status in ('pending','confirmed') and b.ends_at>now()
   order by case when tg_op<>'DELETE' and new.starts_at>=old.starts_at then b.starts_at end desc,
     case when tg_op='DELETE' or new.starts_at<old.starts_at then b.starts_at end,b.id loop
  previous_status:=booking.status;
  if cancel_bookings then
   update core.booking_bookings set status='cancelled',revision=revision+1 where id=booking.id;
  else
   new_start:=booking.starts_at+(new.starts_at-old.starts_at);
   new_end:=booking.ends_at+(new.ends_at-old.ends_at);
   select * into resource from core.booking_resources where id=booking.resource_id;
   if not resource.active then
    raise check_violation using message='event_booking_inactive',detail=jsonb_build_object('resource_name',resource.name)::text;end if;
   if new_end<=new_start or new_end-new_start>interval '31 days' or new_end<=now() then
    raise check_violation using message='event_booking_invalid_time',detail=jsonb_build_object('resource_name',resource.name)::text;end if;
   if not internal.booking_within_disposition(resource,new_start,new_end) then
    raise check_violation using message='event_booking_outside_hours',detail=jsonb_build_object('resource_name',resource.name)::text;end if;
   begin
    update core.booking_bookings set starts_at=new_start,ends_at=new_end,revision=revision+1,
      status=case when resource.requires_approval and internal.booking_actor_role(organization_id) is distinct from 'admin' then 'pending' else status end,
      decided_by=case when resource.requires_approval and internal.booking_actor_role(organization_id) is distinct from 'admin' then null else decided_by end,
      decided_at=case when resource.requires_approval and internal.booking_actor_role(organization_id) is distinct from 'admin' then null else decided_at end
     where id=booking.id;
   exception when exclusion_violation then
    raise exclusion_violation using message='event_booking_conflict',detail=jsonb_build_object('resource_name',resource.name)::text;
   end;
   if previous_status='confirmed' and resource.requires_approval and internal.booking_actor_role(booking.organization_id) is distinct from 'admin' then
    request_ids:=array_append(request_ids,booking.id);end if;
  end if;
  changed_ids:=array_append(changed_ids,booking.id);
 end loop;
 -- One notice per booking group and recipient, even when several resources move.
 for notice in select distinct on(coalesce(b.group_id,b.id),b.booked_by) b.* from core.booking_bookings b
   where b.id=any(changed_ids) order by coalesce(b.group_id,b.id),b.booked_by,b.id loop
  perform internal.booking_notify(notice.id,case when cancel_bookings then 'cancelled' else 'rescheduled' end,array[notice.booked_by]);
 end loop;
 for notice in select distinct on(coalesce(b.group_id,b.id)) b.* from core.booking_bookings b
   where b.id=any(request_ids) order by coalesce(b.group_id,b.id),b.id loop
  perform internal.booking_notify(notice.id,'requested',array(select profile_id from internal.booking_admin_profiles(notice.organization_id)));
 end loop;
 return coalesce(new,old);
end; $$;
revoke all on function internal.sync_bookings_from_event() from public,anon,authenticated;
create trigger event_booking_sync after update of starts_at,ends_at,state,archived_at on core.events
 for each row execute function internal.sync_bookings_from_event();
create function internal.guard_event_booking_history() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
 if exists(select 1 from core.booking_bookings where event_id=old.id) then
  raise check_violation using message='event_booking_history';end if;
 return old;
end; $$;
revoke all on function internal.guard_event_booking_history() from public,anon,authenticated;
create trigger event_booking_delete before delete on core.events
 for each row execute function internal.guard_event_booking_history();

alter table core.booking_notifications drop constraint booking_notifications_kind_check;
alter table core.booking_notifications add constraint booking_notifications_kind_check
 check(kind in ('requested','approved','declined','cancelled','rescheduled'));

CREATE OR REPLACE FUNCTION internal.create_booking_for_actor(target_resource_id uuid, booking_starts_at timestamp with time zone, booking_ends_at timestamp with time zone, booking_title text, booking_notes text, target_team_id uuid, target_event_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  resource core.booking_resources;
  actor_role text;
  created core.booking_bookings;
  event_row core.events;
begin
  if target_event_id is not null then perform 1 from core.events where id=target_event_id for update;end if;
  perform internal.lock_booking_organization((select organization_id from core.booking_resources where id=target_resource_id));
  select * into resource from core.booking_resources where id = target_resource_id for share;
  actor_role := internal.booking_actor_role(resource.organization_id);
  if resource.id is null or actor_role is null then raise insufficient_privilege using message = 'not_found'; end if;
  if not resource.active then raise invalid_parameter_value using message = 'resource_inactive'; end if;
  if booking_ends_at <= booking_starts_at or booking_ends_at - booking_starts_at > interval '31 days' then
    raise invalid_parameter_value using message = 'invalid_time';
  end if;
  if booking_ends_at <= now() then raise invalid_parameter_value using message = 'in_the_past'; end if;
  if target_team_id is not null and not internal.booking_actor_can_book_team(resource.organization_id, target_team_id) then
    raise insufficient_privilege using message = 'not_team_leader';
  end if;
  if target_event_id is not null then
    if not exists (select 1 from core.events e join core.booking_organizations o on o.teamzone_club_id = e.club_id where e.id = target_event_id and o.id = resource.organization_id and e.archived_at is null and e.state in ('draft', 'scheduled')) then raise insufficient_privilege using message = 'event_not_found'; end if;
    if target_team_id is null then raise invalid_parameter_value using message = 'event_needs_team'; end if;
    select * into event_row from core.events where id = target_event_id;
    if event_row.id is null or not internal.actor_can_read_event(target_event_id)
      or not exists (select 1 from core.event_teams relation where relation.event_id = target_event_id and relation.team_id = target_team_id) then
      raise insufficient_privilege using message = 'event_not_found';
    end if;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(target_resource_id::text, 0));
  if exists (select 1 from core.booking_bookings other
    where internal.booking_resources_overlap(other.resource_id,target_resource_id) and other.status in ('pending', 'confirmed')
      and other.starts_at < booking_ends_at and other.ends_at > booking_starts_at) then
    raise exclusion_violation using message = 'resource_busy';
  end if;
  insert into core.booking_bookings (organization_id, resource_id, starts_at, ends_at, title, notes, status, booked_by, team_id, event_id,
    decided_by, decided_at)
  values (resource.organization_id, resource.id, booking_starts_at, booking_ends_at, nullif(btrim(booking_title), ''),
    nullif(btrim(booking_notes), ''),
    case when resource.requires_approval and actor_role <> 'admin' then 'pending' else 'confirmed' end,
    auth.uid(), target_team_id, target_event_id,
    case when resource.requires_approval and actor_role <> 'admin' then null else auth.uid() end,
    case when resource.requires_approval and actor_role <> 'admin' then null else now() end)
  returning * into created;
  if created.status = 'pending' then
    perform internal.booking_notify(created.id, 'requested',
      array(select profile_id from internal.booking_admin_profiles(resource.organization_id)));
  end if;
  return internal.booking_json(created, actor_role);
end;
$function$
;

CREATE OR REPLACE FUNCTION internal.create_booking_group_for_actor(target_resource_ids uuid[], booking_starts_at timestamp with time zone, booking_ends_at timestamp with time zone, booking_title text, booking_notes text, target_team_id uuid, target_event_id uuid, dry_run boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  organization uuid;
  actor_role text;
  resource core.booking_resources;
  new_group uuid := gen_random_uuid();
  items jsonb := '[]'::jsonb;
  busy boolean;
  any_busy boolean := false;
  status text;
  first_pending uuid;
  created_id uuid;
begin
  if target_event_id is not null then perform 1 from core.events where id=target_event_id for update;end if;
  perform internal.lock_booking_organization((select organization_id from core.booking_resources where id=any(target_resource_ids) order by organization_id limit 1));
  if target_resource_ids is null or cardinality(target_resource_ids) not between 1 and 10
    or (select count(distinct value) from unnest(target_resource_ids) value) <> cardinality(target_resource_ids) then
    raise invalid_parameter_value using message = 'invalid_resources';
  end if;
  select min(organization_id::text)::uuid, count(distinct organization_id) = 1 and count(*) = cardinality(target_resource_ids)
  into organization, busy
  from core.booking_resources where id = any(target_resource_ids);
  if not coalesce(busy, false) then raise invalid_parameter_value using message = 'invalid_resources'; end if;
  actor_role := internal.booking_actor_role(organization);
  if actor_role is null then raise insufficient_privilege using message = 'not_found'; end if;
  if booking_ends_at <= booking_starts_at or booking_ends_at - booking_starts_at > interval '31 days' then
    raise invalid_parameter_value using message = 'invalid_time';
  end if;
  if booking_ends_at <= now() then raise invalid_parameter_value using message = 'in_the_past'; end if;
  if target_team_id is not null and not internal.booking_actor_can_book_team(organization, target_team_id) then
    raise insufficient_privilege using message = 'not_team_leader';
  end if;
  if target_event_id is not null then
    if not exists (select 1 from core.events e join core.booking_organizations o on o.teamzone_club_id = e.club_id where e.id = target_event_id and o.id = organization and e.archived_at is null and e.state in ('draft', 'scheduled')) then raise insufficient_privilege using message = 'event_not_found'; end if;
    if target_team_id is null then raise invalid_parameter_value using message = 'event_needs_team'; end if;
    if not exists (select 1 from core.events where id = target_event_id) or not internal.actor_can_read_event(target_event_id)
      or not exists (select 1 from core.event_teams relation where relation.event_id = target_event_id and relation.team_id = target_team_id) then
      raise insufficient_privilege using message = 'event_not_found';
    end if;
  end if;
  perform 1 from core.booking_resources where id = any(target_resource_ids) order by id for share;
  -- Locks in a fixed order, so two groups cannot wait for each other.
  perform pg_advisory_xact_lock(hashtextextended(value::text, 0))
  from unnest(target_resource_ids) value order by value;
  for resource in select * from core.booking_resources where id = any(target_resource_ids) order by category, name loop
    busy := exists(select 1 from unnest(target_resource_ids) selected(id) where selected.id<>resource.id and internal.booking_resources_overlap(selected.id,resource.id)) or not resource.active or not internal.booking_within_disposition(resource,booking_starts_at,booking_ends_at) or exists (select 1 from core.booking_bookings other
      where internal.booking_resources_overlap(other.resource_id,resource.id) and other.status in ('pending', 'confirmed')
        and other.starts_at < booking_ends_at and other.ends_at > booking_starts_at);
    any_busy := any_busy or busy;
    items := items || jsonb_build_object('resource_id', resource.id, 'name', resource.name, 'busy', busy,
      'requires_approval', resource.requires_approval and actor_role <> 'admin');
  end loop;
  if dry_run then return jsonb_build_object('group_id', null, 'items', items); end if;
  if any_busy then raise exclusion_violation using message = 'resource_busy'; end if;
  for resource in select * from core.booking_resources where id = any(target_resource_ids) order by category, name loop
    status := case when resource.requires_approval and actor_role <> 'admin' then 'pending' else 'confirmed' end;
    insert into core.booking_bookings (organization_id, resource_id, starts_at, ends_at, title, notes, status, booked_by,
      team_id, event_id, group_id, decided_by, decided_at)
    values (organization, resource.id, booking_starts_at, booking_ends_at, nullif(btrim(booking_title), ''),
      nullif(btrim(booking_notes), ''), status, auth.uid(), target_team_id, target_event_id, new_group,
      case when status = 'confirmed' then auth.uid() end, case when status = 'confirmed' then now() end)
    returning id into created_id;
    if status = 'pending' and first_pending is null then first_pending := created_id; end if;
  end loop;
  -- One request for the group's resources that need approval.
  if first_pending is not null then
    perform internal.booking_notify(first_pending, 'requested',
      array(select profile_id from internal.booking_admin_profiles(organization)));
  end if;
  return jsonb_build_object('group_id', new_group, 'items', items,
    'pending', (select count(*) from core.booking_bookings b where b.group_id = new_group and b.status = 'pending'));
end;
$function$
;

CREATE OR REPLACE FUNCTION internal.revise_event_v2_for_actor(target_event_id uuid, change_scope text, patch jsonb, expected_revision bigint, idempotency_key uuid)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor_id uuid:=auth.uid();anchor core.events%rowtype;event_target core.events%rowtype;
 existing jsonb;new_revision bigint;new_location_id uuid;location_value text;
 audience_values text[];new_start timestamptz;new_end timestamptz;start_delta interval;
 anchor_new_start timestamptz;anchor_new_end timestamptz;new_duration interval;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='event.event.revise.v2'
  and internal.command_deduplication.idempotency_key=revise_event_v2_for_actor.idempotency_key;
 if existing is not null then return(existing->>'revision')::bigint;end if;
 perform pg_advisory_xact_lock(hashtextextended('event-series:'||coalesce((select recurrence_id from core.events where id=target_event_id),target_event_id)::text,0));
 select * into anchor from core.events where id=target_event_id for update;
 if anchor.id is null or not internal.actor_can_manage_event(anchor.id)
 then raise insufficient_privilege using message='not_found';end if;
 if anchor.revision<>expected_revision then raise sqlstate 'PT409' using message='stale_revision';end if;
 if change_scope not in('one','forward','all') or(anchor.recurrence_id is null and change_scope<>'one')
  or exists(select 1 from jsonb_object_keys(patch) key where key not in
   ('title','description','event_type','starts_at','ends_at','all_day','timezone','location_name','audience_types','callups_required'))
  or(patch?'callups_required' and jsonb_typeof(patch->'callups_required') is distinct from 'boolean')
  or(patch?'title' and length(btrim(patch->>'title')) not between 1 and 160)
  or(patch?'event_type' and patch->>'event_type' not in('training','match','meeting','activity'))
  or(patch?'timezone' and length(btrim(patch->>'timezone')) not between 1 and 80)
  or(patch?'location_name' and length(btrim(patch->>'location_name'))>160)
 then raise invalid_parameter_value using message='invalid_input';end if;

 if patch?'audience_types' then
  select array_agg(value) into audience_values
  from jsonb_array_elements_text(patch->'audience_types') value;
  if audience_values is null or cardinality(audience_values)=0
   or exists(select 1 from unnest(audience_values) value where value not in('players','leaders','guardians','club'))
   or cardinality(audience_values)<>(select count(distinct value) from unnest(audience_values) value)
  then raise invalid_parameter_value using message='invalid_audience';end if;
 end if;

 anchor_new_start:=case when patch?'starts_at' then(patch->>'starts_at')::timestamptz else anchor.starts_at end;
 anchor_new_end:=case when patch?'ends_at' then(patch->>'ends_at')::timestamptz
  when patch?'starts_at' then anchor.ends_at+(anchor_new_start-anchor.starts_at) else anchor.ends_at end;
 if anchor_new_end<=anchor_new_start then raise invalid_parameter_value using message='invalid_period';end if;
 start_delta:=anchor_new_start-anchor.starts_at;new_duration:=anchor_new_end-anchor_new_start;

 if patch?'location_name' then
  location_value:=nullif(btrim(patch->>'location_name'),'');
  if location_value is not null then
   select location.id into new_location_id from core.event_locations location
   where location.club_id=anchor.club_id and lower(btrim(location.name))=lower(location_value)
   order by location.created_at desc limit 1;
   if new_location_id is null then
    insert into core.event_locations(club_id,name,created_by)
    values(anchor.club_id,location_value,actor_id) returning id into new_location_id;
   end if;
  end if;
 end if;

 perform pg_advisory_xact_lock(hashtextextended('event-series:'||coalesce(anchor.recurrence_id,anchor.id)::text,0));
 if anchor.recurrence_id is not null and change_scope='all' and(patch?'starts_at' or patch?'timezone') then
  update core.recurrence_rules set local_start=anchor_new_start at time zone
    case when patch?'timezone' then btrim(patch->>'timezone') else timezone end,
   timezone=case when patch?'timezone' then btrim(patch->>'timezone') else timezone end,
   revision=revision+1 where id=anchor.recurrence_id;
 end if;
 perform 1 from core.events event_row where event_row.id=anchor.id
  or(anchor.recurrence_id is not null and event_row.recurrence_id=anchor.recurrence_id
   and(change_scope='all' or change_scope='forward' and event_row.occurrence_number>=anchor.occurrence_number))
  order by event_row.occurrence_number nulls first for update;
 -- Acquire every organisation before moving the first occurrence.
 perform internal.lock_booking_organization(target.organization_id) from (
  select distinct b.organization_id from core.booking_bookings b join core.events e on e.id=b.event_id
  where b.status in ('pending','confirmed') and b.ends_at>now() and (e.id=anchor.id or
   (anchor.recurrence_id is not null and e.recurrence_id=anchor.recurrence_id and
    (change_scope='all' or change_scope='forward' and e.occurrence_number>=anchor.occurrence_number)))
  order by b.organization_id
 ) target;
 for event_target in select event_row.* from core.events event_row where event_row.id=anchor.id
  or(anchor.recurrence_id is not null and event_row.recurrence_id=anchor.recurrence_id
   and(change_scope='all' or change_scope='forward' and event_row.occurrence_number>=anchor.occurrence_number))
  order by case when start_delta>=interval '0' then event_row.starts_at end desc,
   case when start_delta<interval '0' then event_row.starts_at end,event_row.id loop
  new_start:=case when patch?'starts_at' then event_target.starts_at+start_delta else event_target.starts_at end;
  new_end:=case when patch?'ends_at' then new_start+new_duration
   when patch?'starts_at' then event_target.ends_at+start_delta else event_target.ends_at end;
  if new_end<=new_start then raise invalid_parameter_value using message='invalid_period';end if;
  update core.events set title=case when patch?'title' then btrim(patch->>'title') else title end,
   description=case when patch?'description' then nullif(btrim(patch->>'description'),'') else description end,
   event_type=case when patch?'event_type' then patch->>'event_type' else event_type end,
   starts_at=new_start,ends_at=new_end,
   callups_required=case when patch?'callups_required' then (patch->>'callups_required')::boolean else callups_required end,
   all_day=case when patch?'all_day' then(patch->>'all_day')::boolean else all_day end,
   timezone=case when patch?'timezone' then btrim(patch->>'timezone') else timezone end,
   location_id=case when patch?'location_name' then new_location_id else location_id end,
   updated_at=now(),revision=revision+1 where id=event_target.id returning revision into new_revision;
  if patch?'audience_types' then
   delete from core.event_audiences where event_id=event_target.id
    and(team_id=event_target.owning_team_id or team_id is null);
   insert into core.event_audiences(club_id,event_id,audience_type,team_id,created_by)
   select event_target.club_id,event_target.id,value,case when value='club' then null else event_target.owning_team_id end,actor_id
   from unnest(audience_values) value;
  end if;
  insert into core.event_revisions(club_id,event_id,event_revision,action,scope,snapshot,actor_profile_id)
  select event_target.club_id,event_target.id,new_revision,'revised',change_scope,internal.event_snapshot(current_row),actor_id
  from core.events current_row where current_row.id=event_target.id;
  insert into internal.domain_outbox(club_id,event_type,aggregate_type,aggregate_id,aggregate_revision,payload)
  values(event_target.club_id,'event.event.revised.v1','event',event_target.id,new_revision,jsonb_build_object('scope',change_scope));
 end loop;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'event.event.revise.v2',jsonb_build_object('revision',new_revision));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,
  aggregate_revision,metadata) values(anchor.club_id,actor_id,'event.event.revise.v2','event',anchor.id,
  new_revision,jsonb_build_object('scope',change_scope,'fields',(select jsonb_agg(key) from jsonb_object_keys(patch) key)));
 return new_revision;
end;
$function$
;

do $command$
declare definition text; patched text;
begin
 definition:=pg_get_functiondef('internal.execute_booking_command_for_actor(uuid,text,jsonb,jsonb)'::regprocedure);
 patched:=replace(definition,'  case command_type',
  '  if command_type in (''create_booking'',''create_booking_group'') and p->>''target_event_id'' is not null
    and (p ? ''expected_event_starts_at'' or p ? ''expected_event_ends_at'') then
    perform 1 from core.events where id=(p->>''target_event_id'')::uuid for update;
    if not internal.actor_can_read_event((p->>''target_event_id'')::uuid) then
      raise insufficient_privilege using message=''event_not_found'';end if;
    if not exists(select 1 from core.events e where e.id=(p->>''target_event_id'')::uuid
      and e.starts_at=(p->>''expected_event_starts_at'')::timestamptz
      and e.ends_at=(p->>''expected_event_ends_at'')::timestamptz) then
      raise sqlstate ''PT409'' using message=''event_changed'';end if;
  end if;
  case command_type');
 if patched=definition then raise exception 'Booking command contract changed';end if;execute patched;
end;$command$;

do $notification$
declare definition text; patched text;
begin
 definition:=pg_get_functiondef('internal.push_message_for_outbox(uuid)'::regprocedure);
 patched:=replace(definition, 'when ''booking.requested.v1'' then',
  'when ''booking.rescheduled.v1'' then case when swedish then U&''Bokningen har f\00e5tt ny tid'' else ''Booking rescheduled'' end
      when ''booking.requested.v1'' then');
 if patched=definition then raise exception 'Booking push formatter contract changed';end if;execute patched;
 definition:=pg_get_functiondef('internal.notification_title(text)'::regprocedure);
 patched:=replace(definition,'when event_type = ''booking.requested.v1'' then',
  'when event_type = ''booking.rescheduled.v1'' then U&''Bokningen har f\00e5tt ny tid''
  when event_type = ''booking.requested.v1'' then');
 if patched=definition then raise exception 'Booking title formatter contract changed';end if;execute patched;
 definition:=pg_get_functiondef('internal.notification_preview(text)'::regprocedure);
 patched:=replace(definition,'when event_type = ''booking.requested.v1'' then',
  'when event_type = ''booking.rescheduled.v1'' then U&''Aktiviteten och dess resursbokning har flyttats. Se de nya tiderna i Bokningshanteraren.''
  when event_type = ''booking.requested.v1'' then');
 if patched=definition then raise exception 'Booking preview formatter contract changed';end if;execute patched;
end;$notification$;
