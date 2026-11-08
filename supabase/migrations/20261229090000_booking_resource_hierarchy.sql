-- A resource can contain resources which can themselves be subdivided.
-- Exclusive leaf claims make ancestor/descendant conflicts a storage invariant.
alter table core.booking_resources add column parent_resource_id uuid references core.booking_resources(id);
create index booking_resource_parent on core.booking_resources(parent_resource_id);

create function internal.lock_booking_organization(org uuid) returns void
language sql volatile set search_path = '' as $$
  select pg_advisory_xact_lock(hashtextextended(org::text,43291))
$$;
revoke all on function internal.lock_booking_organization(uuid) from public,anon,authenticated;

create function internal.booking_resource_ancestors(resource_id uuid) returns table(id uuid)
language sql stable set search_path = '' as $$
  with recursive ancestors as (
    select r.id,r.parent_resource_id from core.booking_resources r where r.id=resource_id
    union
    select p.id,p.parent_resource_id from core.booking_resources p join ancestors a on a.parent_resource_id=p.id
  ) select a.id from ancestors a
$$;
create function internal.booking_resource_leaves(resource_id uuid) returns table(id uuid)
language sql stable set search_path = '' as $$
  with recursive descendants as (
    select r.id from core.booking_resources r where r.id=resource_id
    union
    select c.id from core.booking_resources c join descendants p on c.parent_resource_id=p.id
  ) select d.id from descendants d where not exists(select 1 from core.booking_resources c where c.parent_resource_id=d.id)
$$;
create function internal.booking_resources_overlap(first_id uuid,second_id uuid) returns boolean
language sql stable set search_path = '' as $$
 select exists(select 1 from internal.booking_resource_ancestors(first_id) a where a.id=second_id)
   or exists(select 1 from internal.booking_resource_ancestors(second_id) a where a.id=first_id)
$$;
revoke all on function internal.booking_resource_ancestors(uuid),internal.booking_resource_leaves(uuid),internal.booking_resources_overlap(uuid,uuid) from public,anon,authenticated;

create table internal.booking_resource_claims (
 booking_id uuid not null references core.booking_bookings(id) on delete cascade,
 organization_id uuid not null references core.booking_organizations(id) on delete cascade,
 leaf_id uuid not null references core.booking_resources(id) on delete cascade,
 starts_at timestamptz not null, ends_at timestamptz not null,
 primary key(booking_id,leaf_id),
 constraint booking_leaf_no_overlap exclude using gist(leaf_id with =,tstzrange(starts_at,ends_at,'[)') with &&)
);
alter table internal.booking_resource_claims enable row level security;
revoke all on internal.booking_resource_claims from public,anon,authenticated;
create index booking_resource_claims_org on internal.booking_resource_claims(organization_id);

create function internal.guard_booking_hierarchy() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
 perform internal.lock_booking_organization(new.organization_id);
 if new.status in ('pending','confirmed') and exists(
   select 1 from core.booking_bookings b where b.id<>new.id and b.resource_id<>new.resource_id and b.organization_id=new.organization_id
   and b.status in ('pending','confirmed') and b.starts_at<new.ends_at and b.ends_at>new.starts_at
   and internal.booking_resources_overlap(new.resource_id,b.resource_id)) then
   raise exclusion_violation using message='resource_busy'; end if;
 return new;
end; $$;
create trigger booking_00_hierarchy before insert or update of resource_id,starts_at,ends_at,status,organization_id on core.booking_bookings
 for each row execute function internal.guard_booking_hierarchy();

create function internal.sync_booking_resource_claims() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
 delete from internal.booking_resource_claims where booking_id=new.id;
 if new.status in ('pending','confirmed') then
  insert into internal.booking_resource_claims(booking_id,organization_id,leaf_id,starts_at,ends_at)
   select new.id,new.organization_id,l.id,new.starts_at,new.ends_at from internal.booking_resource_leaves(new.resource_id) l;
 end if;
 return new;
end; $$;
create trigger booking_claims after insert or update of resource_id,starts_at,ends_at,status,organization_id on core.booking_bookings
 for each row execute function internal.sync_booking_resource_claims();

create function internal.guard_booking_resource_hierarchy() returns trigger
language plpgsql security definer set search_path = '' as $$
declare parent core.booking_resources;
begin
 if tg_op='UPDATE' and new.organization_id<>old.organization_id then
  raise check_violation using message='invalid_resource_hierarchy';end if;
 if tg_op='INSERT' or new.parent_resource_id is distinct from old.parent_resource_id then
  perform internal.lock_booking_organization(new.organization_id);
  if new.parent_resource_id is not null then
   select * into parent from core.booking_resources where id=new.parent_resource_id;
   if parent.id is null or parent.organization_id<>new.organization_id or parent.id=new.id
     or exists(select 1 from internal.booking_resource_ancestors(parent.id) a where a.id=new.id) then
     raise check_violation using message='invalid_resource_hierarchy';end if;
  end if;
 end if;
 return new;
end; $$;
create trigger booking_resource_00_hierarchy before insert or update on core.booking_resources
 for each row execute function internal.guard_booking_resource_hierarchy();

create function internal.rebuild_booking_hierarchy_claims() returns trigger
language plpgsql security definer set search_path = '' as $$
declare org uuid:=coalesce(new.organization_id,old.organization_id);
begin
 if not exists(select 1 from core.booking_organizations where id=org) then return coalesce(new,old);end if;
 if tg_op='UPDATE' and new.parent_resource_id is not distinct from old.parent_resource_id then return new;end if;
 if tg_op='INSERT' and new.parent_resource_id is null then return new;end if;
 perform internal.lock_booking_organization(org);
 if tg_op<>'DELETE' and new.parent_resource_id is not null and exists(
   select 1 from internal.booking_resource_ancestors(new.parent_resource_id) a where a.id=new.id) then
   raise check_violation using message='invalid_resource_hierarchy';end if;
 if exists(select 1 from core.booking_bookings b join core.booking_resources r on r.id=b.resource_id
    where b.organization_id=org and b.status in ('pending','confirmed') and b.ends_at>now()
    and not internal.booking_within_disposition(r,b.starts_at,b.ends_at)) then
   raise check_violation using message='hierarchy_has_bookings';end if;
 -- Past reservations retain their recorded resource; only remaining time needs claims.
 delete from internal.booking_resource_claims where organization_id=org;
 begin
  insert into internal.booking_resource_claims(booking_id,organization_id,leaf_id,starts_at,ends_at)
   select b.id,b.organization_id,l.id,b.starts_at,b.ends_at from core.booking_bookings b
   cross join lateral internal.booking_resource_leaves(b.resource_id) l
   where b.organization_id=org and b.status in ('pending','confirmed') and b.ends_at>now();
 exception when exclusion_violation then raise exclusion_violation using message='hierarchy_has_bookings';end;
 return coalesce(new,old);
end; $$;
create trigger booking_resource_claims after insert or update of parent_resource_id or delete on core.booking_resources
 for each row execute function internal.rebuild_booking_hierarchy_claims();
revoke all on function internal.guard_booking_hierarchy(),internal.sync_booking_resource_claims(),internal.guard_booking_resource_hierarchy(),internal.rebuild_booking_hierarchy_claims() from public,anon,authenticated;

-- Existing resources are independent, so each active booking initially claims itself.
insert into internal.booking_resource_claims(booking_id,organization_id,leaf_id,starts_at,ends_at)
 select b.id,b.organization_id,b.resource_id,b.starts_at,b.ends_at from core.booking_bookings b
 where b.status in ('pending','confirmed') and b.ends_at>now();

create or replace function internal.booking_within_resource_hours(resource core.booking_resources, starts_at timestamptz, ends_at timestamptz)
returns boolean language plpgsql stable set search_path = '' as $$
declare day date; last_day date; windows jsonb; spans tstzmultirange := '{}'::tstzmultirange;
  slot jsonb; lo timestamptz; hi timestamptz;
begin
  if starts_at is null or ends_at is null or not isfinite(starts_at) or not isfinite(ends_at)
    or ends_at<=starts_at or ends_at-starts_at>interval '31 days' then return false; end if;
  if (resource.available_from is not null and starts_at < resource.available_from::timestamp at time zone resource.timezone)
    or (resource.available_until is not null and ends_at > (resource.available_until+1)::timestamp at time zone resource.timezone) then return false; end if;
  if resource.availability->>'mode'='always' and resource.availability->'exceptions'='[]'::jsonb then return true; end if;
  day := (starts_at at time zone resource.timezone)::date;
  last_day := (ends_at at time zone resource.timezone)::date;
  while day<=last_day loop
    select e.value->'windows' into windows from jsonb_array_elements(resource.availability->'exceptions') e where e.value->>'date'=day::text;
    if windows is null then
      if resource.availability->>'mode'='always' then windows := '[{"start":0,"end":1440}]'::jsonb;
      else select coalesce(jsonb_agg(w.value),'[]'::jsonb) into windows from jsonb_array_elements(resource.availability->'weekly') w where (w.value->>'day')::integer=extract(isodow from day)::integer; end if;
    end if;
    for slot in select value from jsonb_array_elements(windows) loop
      lo := (day::timestamp + (slot->>'start')::integer*interval '1 minute') at time zone resource.timezone;
      hi := (day::timestamp + (slot->>'end')::integer*interval '1 minute') at time zone resource.timezone;
      -- A slot_value wholly in the missing spring hour can collapse or invert.
      if hi>lo then spans := spans + tstzmultirange(tstzrange(lo,hi,'[)')); end if;
    end loop;
    day := day+1;
  end loop;
  return tstzrange(starts_at,ends_at,'[)') <@ spans;
end; $$;
revoke all on function internal.booking_within_resource_hours(core.booking_resources,timestamptz,timestamptz) from public,anon,authenticated;

create or replace function internal.booking_within_disposition(resource core.booking_resources, starts_at timestamptz, ends_at timestamptz)
returns boolean language sql stable set search_path = '' as $$
 select internal.booking_within_resource_hours(resource,starts_at,ends_at) and not exists(
   select 1 from internal.booking_resource_ancestors(resource.parent_resource_id) a
   join core.booking_resources p on p.id=a.id where not internal.booking_within_resource_hours(p,starts_at,ends_at))
$$;

create or replace function internal.guard_booking_resource_disposition() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op='INSERT' or (new.ownership_kind,new.owner_name,new.timezone,new.available_from,new.available_until,new.availability)
    is distinct from (old.ownership_kind,old.owner_name,old.timezone,old.available_from,old.available_until,old.availability) then
    perform internal.lock_booking_organization(new.organization_id);end if;
  if not exists(select 1 from pg_catalog.pg_timezone_names where name=new.timezone) then
    raise invalid_parameter_value using message='invalid_timezone'; end if;
  if not internal.validate_booking_availability(new.availability) then
    raise invalid_parameter_value using message='invalid_availability'; end if;
  if tg_op='UPDATE' and (new.ownership_kind,new.owner_name,new.timezone,new.available_from,new.available_until,new.availability)
    is distinct from (old.ownership_kind,old.owner_name,old.timezone,old.available_from,old.available_until,old.availability)
    and exists(select 1 from core.booking_bookings b where exists(select 1 from internal.booking_resource_ancestors(b.resource_id) a where a.id=new.id)
      and b.status in ('pending','confirmed') and b.ends_at>now()
      and not internal.booking_within_disposition(new,b.starts_at,b.ends_at)) then
    raise check_violation using message='disposition_has_bookings'; end if;
  return new;
end; $$;

create or replace function internal.save_booking_resource_v2_for_actor(
  target_organization_id uuid,target_resource_id uuid,details jsonb,expected_revision bigint
) returns uuid language plpgsql security definer set search_path = '' as $$
declare current_resource core.booking_resources; saved uuid; ownership text:=details->>'ownership_kind';
begin
  perform internal.lock_booking_organization(target_organization_id);
  if internal.booking_actor_role(target_organization_id) is distinct from 'admin' then
    raise insufficient_privilege using message='not_admin'; end if;
  if jsonb_typeof(details) is distinct from 'object' or ownership is null
    or ownership not in ('unspecified','owned','external') or nullif(btrim(details->>'timezone'),'') is null
    or (ownership='external' and (nullif(btrim(details->>'owner_name'),'') is null
      or nullif(details->>'available_from','') is null or nullif(details->>'available_until','') is null))
    or ((nullif(details->>'available_from','') is null) <> (nullif(details->>'available_until','') is null)) then
    raise invalid_parameter_value using message='invalid_disposition'; end if;
  if target_resource_id is not null then
    select * into current_resource from core.booking_resources
      where id=target_resource_id and organization_id=target_organization_id for update;
    if current_resource.id is null then raise insufficient_privilege using message='not_found'; end if;
    if expected_revision is null then raise invalid_parameter_value using message='revision_required'; end if;
    if current_resource.revision<>expected_revision then raise sqlstate 'PT409' using message='stale_revision'; end if;
  end if;
  if ownership='unspecified' and current_resource.ownership_kind is distinct from 'unspecified' then
    raise invalid_parameter_value using message='invalid_disposition'; end if;
  if nullif(details->>'available_from','')::date > nullif(details->>'available_until','')::date then
    raise invalid_parameter_value using message='invalid_disposition'; end if;
  if target_resource_id is null then
    insert into core.booking_resources(organization_id,name,category,description,location,capacity,requires_approval,active,
      ownership_kind,owner_name,timezone,available_from,available_until,availability,parent_resource_id)
    values(target_organization_id,btrim(details->>'name'),details->>'category',nullif(btrim(details->>'description'),''),
      nullif(btrim(details->>'location'),''),(details->>'capacity')::integer,coalesce((details->>'requires_approval')::boolean,false),
      coalesce((details->>'active')::boolean,true),ownership,nullif(btrim(details->>'owner_name'),''),details->>'timezone',
      nullif(details->>'available_from','')::date,nullif(details->>'available_until','')::date,coalesce(details->'availability','{"mode":"always","weekly":[],"exceptions":[]}'::jsonb),nullif(details->>'parent_resource_id','')::uuid) returning id into saved;
  else
    update core.booking_resources set name=btrim(details->>'name'),category=details->>'category',
      description=nullif(btrim(details->>'description'),''),location=nullif(btrim(details->>'location'),''),
      capacity=(details->>'capacity')::integer,requires_approval=coalesce((details->>'requires_approval')::boolean,false),
      active=coalesce((details->>'active')::boolean,true),ownership_kind=ownership,owner_name=nullif(btrim(details->>'owner_name'),''),
      timezone=details->>'timezone',available_from=nullif(details->>'available_from','')::date,
      available_until=nullif(details->>'available_until','')::date,
      availability=coalesce(details->'availability',current_resource.availability),
      parent_resource_id=case when details ? 'parent_resource_id' then nullif(details->>'parent_resource_id','')::uuid else current_resource.parent_resource_id end,revision=revision+1 where id=current_resource.id returning id into saved;
  end if;
  return saved;
end; $$;

create or replace function internal.create_booking_for_actor(
  target_resource_id uuid, booking_starts_at timestamptz, booking_ends_at timestamptz,
  booking_title text, booking_notes text, target_team_id uuid, target_event_id uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  resource core.booking_resources;
  actor_role text;
  created core.booking_bookings;
  event_row core.events;
begin
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
$$;

create or replace function internal.create_booking_group_for_actor(
  target_resource_ids uuid[], booking_starts_at timestamptz, booking_ends_at timestamptz,
  booking_title text, booking_notes text, target_team_id uuid, target_event_id uuid, dry_run boolean
) returns jsonb language plpgsql security definer set search_path = '' as $$
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
$$;

create or replace function internal.create_booking_series_for_actor(
  target_resource_id uuid, series_weekdays smallint[], series_interval smallint,
  first_day date, last_day date, start_at time, end_at time, zone text,
  booking_title text, booking_notes text, target_team_id uuid, dry_run boolean
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  resource core.booking_resources;
  actor_role text;
  new_series uuid;
  status text;
  times jsonb := '[]'::jsonb;
  occurrence record;
  clash boolean;
  created integer := 0;
begin
  perform internal.lock_booking_organization((select organization_id from core.booking_resources where id=target_resource_id));
  select * into resource from core.booking_resources where id = target_resource_id for share;
  actor_role := internal.booking_actor_role(resource.organization_id);
  if resource.id is null or actor_role is null then raise insufficient_privilege using message = 'not_found'; end if;
  if not resource.active then raise invalid_parameter_value using message = 'resource_inactive'; end if;
  if series_weekdays is null or cardinality(series_weekdays) = 0 or not (series_weekdays <@ array[1, 2, 3, 4, 5, 6, 7]::smallint[])
    or series_interval not between 1 and 4 or last_day < first_day or last_day - first_day > 366 or end_at <= start_at then
    raise invalid_parameter_value using message = 'invalid_series';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = zone) then
    raise invalid_parameter_value using message = 'invalid_series';
  end if;
  if target_team_id is not null and not internal.booking_actor_can_book_team(resource.organization_id, target_team_id) then
    raise insufficient_privilege using message = 'not_team_leader';
  end if;
  if (select count(*) from internal.booking_series_times(series_weekdays, series_interval, first_day, last_day, start_at, end_at, zone)
      where ends_at > now()) > 200 then
    raise invalid_parameter_value using message = 'series_too_long';
  end if;
  status := case when resource.requires_approval and actor_role <> 'admin' then 'pending' else 'confirmed' end;
  perform pg_advisory_xact_lock(hashtextextended(target_resource_id::text, 0));
  if not dry_run then
    insert into core.booking_series (organization_id, resource_id, booked_by, team_id, title, notes, weekdays, interval_weeks,
      starts_on, ends_on, start_time, end_time, timezone)
    values (resource.organization_id, resource.id, auth.uid(), target_team_id, nullif(btrim(booking_title), ''),
      nullif(btrim(booking_notes), ''), series_weekdays, series_interval, first_day, last_day, start_at, end_at, zone)
    returning id into new_series;
  end if;
  for occurrence in
    select * from internal.booking_series_times(series_weekdays, series_interval, first_day, last_day, start_at, end_at, zone)
    where ends_at > now()
  loop
    clash := not internal.booking_within_disposition(resource,occurrence.starts_at,occurrence.ends_at) or exists (select 1 from core.booking_bookings other
      where internal.booking_resources_overlap(other.resource_id,target_resource_id) and other.status in ('pending', 'confirmed')
        and other.starts_at < occurrence.ends_at and other.ends_at > occurrence.starts_at);
    times := times || jsonb_build_object('starts_at', occurrence.starts_at, 'ends_at', occurrence.ends_at, 'clash', clash, 'outside_disposition',not internal.booking_within_disposition(resource,occurrence.starts_at,occurrence.ends_at));
    if not clash and not dry_run then
      insert into core.booking_bookings (organization_id, resource_id, starts_at, ends_at, title, notes, status, booked_by,
        team_id, series_id, decided_by, decided_at)
      values (resource.organization_id, resource.id, occurrence.starts_at, occurrence.ends_at, nullif(btrim(booking_title), ''),
        nullif(btrim(booking_notes), ''), status, auth.uid(), target_team_id, new_series,
        case when status = 'confirmed' then auth.uid() end, case when status = 'confirmed' then now() end);
      created := created + 1;
    end if;
  end loop;
  if not dry_run then
    if created = 0 then
      delete from core.booking_series where id = new_series;
      raise exclusion_violation using message = 'resource_busy';
    end if;
    -- One request for the whole series.
    if status = 'pending' then
      perform internal.booking_notify(
        (select b.id from core.booking_bookings b where b.series_id = new_series order by b.starts_at limit 1),
        'requested', array(select profile_id from internal.booking_admin_profiles(resource.organization_id)));
    end if;
  end if;
  return jsonb_build_object('series_id', new_series, 'status', status, 'created', created, 'times', times);
end;
$$;

create or replace function internal.get_booking_organization_for_actor(target_organization_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare actor_role text := internal.booking_actor_role(target_organization_id);
begin
  if actor_role is null then raise insufficient_privilege using message = 'not_found'; end if;
  return (
    select jsonb_build_object(
      'id', org.id, 'name', org.name, 'kind', org.kind, 'sport', org.sport,
      'teamzone_club_id', org.teamzone_club_id,
      'teamzone_club_name', (select club.name from core.clubs club where club.id = org.teamzone_club_id),
      'club_members_can_book', org.club_members_can_book,
      'role', actor_role,
      'resources', coalesce((select jsonb_agg(jsonb_build_object(
          'id', resource.id, 'parent_resource_id',resource.parent_resource_id, 'name', resource.name, 'category', resource.category,
          'description', resource.description, 'location', resource.location,
          'capacity', resource.capacity, 'requires_approval', resource.requires_approval,
          'active', resource.active, 'revision', resource.revision,
          'ownership_kind',resource.ownership_kind,'owner_name',resource.owner_name,'timezone',resource.timezone,
          'availability',resource.availability,'available_from',resource.available_from,'available_until',resource.available_until
        ) order by resource.active desc, resource.category, resource.name)
        from core.booking_resources resource
        where resource.organization_id = org.id and (resource.active or actor_role = 'admin')), '[]'::jsonb),
      'members', case when actor_role = 'admin' then coalesce((select jsonb_agg(jsonb_build_object(
          'profile_id', member.profile_id, 'name', internal.booking_person_name(member.profile_id),
          'role', member.role, 'is_self', member.profile_id = auth.uid()
        ) order by member.role, internal.booking_person_name(member.profile_id))
        from core.booking_members member where member.organization_id = org.id), '[]'::jsonb) end,
      'teams', coalesce((select jsonb_agg(jsonb_build_object('team_id', t.team_id, 'name', t.team_name) order by t.team_name)
        from (select team.id team_id, team.name team_name from core.teams team where team.club_id = org.teamzone_club_id and team.status = 'active' and internal.booking_actor_can_book_team(org.id, team.id)) t), '[]'::jsonb),
      'pending_count', case when actor_role = 'admin' then (select count(*) from core.booking_bookings booking
        where booking.organization_id = org.id and booking.status = 'pending' and booking.ends_at > now()) end
    )
    from core.booking_organizations org where org.id = target_organization_id
  );
end;
$$;

create or replace function internal.list_booking_availability_for_actor(
  target_organization_id uuid, range_start timestamptz, range_end timestamptz
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if internal.booking_actor_role(target_organization_id) is null then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if range_end <= range_start or range_end - range_start > interval '31 days' then
    raise invalid_parameter_value using message = 'invalid_time';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'resource_id', resource.id, 'name', resource.name, 'category', resource.category,
      'location', resource.location, 'requires_approval', resource.requires_approval,
      'busy', clash.id is not null or not internal.booking_within_disposition(resource,range_start,range_end),
      'timezone',resource.timezone,'ownership_kind',resource.ownership_kind,
      'outside_disposition',not internal.booking_within_disposition(resource,range_start,range_end),
      'busy_with', case when not internal.booking_within_disposition(resource,range_start,range_end) then U&'Utanf\00f6r resursens bokningsbara tider' when clash.id is null then null else coalesce(
        (select team.name from core.teams team where team.id = clash.team_id), clash.title,
        internal.booking_person_name(clash.booked_by)) end,
      'busy_resource_id',clash.resource_id,'busy_resource_name',(select name from core.booking_resources where id=clash.resource_id),
      'busy_from', clash.starts_at, 'busy_to', clash.ends_at
    ) order by resource.category, resource.name)
    from core.booking_resources resource
    left join lateral (
      select other.id, other.resource_id, other.team_id, other.title, other.booked_by, other.starts_at, other.ends_at
      from core.booking_bookings other
      where internal.booking_resources_overlap(other.resource_id,resource.id) and other.status in ('pending', 'confirmed')
        and other.starts_at < range_end and other.ends_at > range_start
      order by other.starts_at limit 1
    ) clash on true
    where resource.organization_id = target_organization_id and resource.active), '[]'::jsonb);
end;
$$;
