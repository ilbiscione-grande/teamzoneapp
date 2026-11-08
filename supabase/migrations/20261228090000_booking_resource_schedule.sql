-- Local weekly windows and date overrides. Empty overrides close the date.
-- All configuration lives on the locked resource row; legacy writes retain it.
alter table core.booking_resources add column availability jsonb not null
  default '{"mode":"always","weekly":[],"exceptions":[]}'::jsonb;

create function internal.validate_booking_availability(plan jsonb) returns boolean
language plpgsql immutable set search_path = '' as $$
declare entry jsonb; slot_value jsonb;
begin
  if jsonb_typeof(plan) is distinct from 'object' or coalesce(plan->>'mode','') not in ('always','weekly')
    or jsonb_typeof(plan->'weekly') is distinct from 'array'
    or jsonb_typeof(plan->'exceptions') is distinct from 'array' then return false; end if;
  if jsonb_array_length(plan->'weekly')>56 or jsonb_array_length(plan->'exceptions')>366 then return false; end if;
  for entry in select value from jsonb_array_elements(plan->'weekly') loop
    if jsonb_typeof(entry) is distinct from 'object' or jsonb_typeof(entry->'day') is distinct from 'number'
      or coalesce(entry->>'day','') !~ '^[1-7]$' then return false; end if;
  end loop;
  for entry in select value from jsonb_array_elements(plan->'exceptions') loop
    if jsonb_typeof(entry) is distinct from 'object' or jsonb_typeof(entry->'date') is distinct from 'string'
      or coalesce(entry->>'date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
      or jsonb_typeof(entry->'windows') is distinct from 'array' then return false; end if;
    perform make_date(substring(entry->>'date',1,4)::integer,substring(entry->>'date',6,2)::integer,substring(entry->>'date',9,2)::integer);
    if jsonb_array_length(entry->'windows')>8 then return false; end if;
  end loop;
  if (select count(*)<>count(distinct value->>'date') from jsonb_array_elements(plan->'exceptions')) then return false; end if;
  for slot_value in
    select value from jsonb_array_elements(plan->'weekly')
    union all select w.value from jsonb_array_elements(plan->'exceptions') e cross join lateral jsonb_array_elements(e.value->'windows') w
  loop
    if jsonb_typeof(slot_value) is distinct from 'object'
      or jsonb_typeof(slot_value->'start') is distinct from 'number' or jsonb_typeof(slot_value->'end') is distinct from 'number'
      or coalesce(slot_value->>'start','') !~ '^[0-9]{1,4}$' or coalesce(slot_value->>'end','') !~ '^[0-9]{1,4}$' then return false; end if;
    if (slot_value->>'start')::integer not between 0 and 1439 or (slot_value->>'end')::integer not between 1 and 1440
      or (slot_value->>'end')::integer <= (slot_value->>'start')::integer then return false; end if;
  end loop;
  return true;
exception when invalid_datetime_format or datetime_field_overflow then return false;
end; $$;
revoke all on function internal.validate_booking_availability(jsonb) from public,anon,authenticated;

create or replace function internal.booking_within_disposition(resource core.booking_resources, starts_at timestamptz, ends_at timestamptz)
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

create or replace function internal.guard_booking_resource_disposition() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not exists(select 1 from pg_catalog.pg_timezone_names where name=new.timezone) then
    raise invalid_parameter_value using message='invalid_timezone'; end if;
  if not internal.validate_booking_availability(new.availability) then
    raise invalid_parameter_value using message='invalid_availability'; end if;
  if tg_op='UPDATE' and (new.ownership_kind,new.owner_name,new.timezone,new.available_from,new.available_until,new.availability)
    is distinct from (old.ownership_kind,old.owner_name,old.timezone,old.available_from,old.available_until,old.availability)
    and exists(select 1 from core.booking_bookings b where b.resource_id=new.id
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
      ownership_kind,owner_name,timezone,available_from,available_until,availability)
    values(target_organization_id,btrim(details->>'name'),details->>'category',nullif(btrim(details->>'description'),''),
      nullif(btrim(details->>'location'),''),(details->>'capacity')::integer,coalesce((details->>'requires_approval')::boolean,false),
      coalesce((details->>'active')::boolean,true),ownership,nullif(btrim(details->>'owner_name'),''),details->>'timezone',
      nullif(details->>'available_from','')::date,nullif(details->>'available_until','')::date,coalesce(details->'availability','{"mode":"always","weekly":[],"exceptions":[]}'::jsonb)) returning id into saved;
  else
    update core.booking_resources set name=btrim(details->>'name'),category=details->>'category',
      description=nullif(btrim(details->>'description'),''),location=nullif(btrim(details->>'location'),''),
      capacity=(details->>'capacity')::integer,requires_approval=coalesce((details->>'requires_approval')::boolean,false),
      active=coalesce((details->>'active')::boolean,true),ownership_kind=ownership,owner_name=nullif(btrim(details->>'owner_name'),''),
      timezone=details->>'timezone',available_from=nullif(details->>'available_from','')::date,
      available_until=nullif(details->>'available_until','')::date,
      availability=coalesce(details->'availability',current_resource.availability),revision=revision+1 where id=current_resource.id returning id into saved;
  end if;
  return saved;
end; $$;

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
          'id', resource.id, 'name', resource.name, 'category', resource.category,
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
      'busy_from', clash.starts_at, 'busy_to', clash.ends_at
    ) order by resource.category, resource.name)
    from core.booking_resources resource
    left join lateral (
      select other.id, other.team_id, other.title, other.booked_by, other.starts_at, other.ends_at
      from core.booking_bookings other
      where other.resource_id = resource.id and other.status in ('pending', 'confirmed')
        and other.starts_at < range_end and other.ends_at > range_start
      order by other.starts_at limit 1
    ) clash on true
    where resource.organization_id = target_organization_id and resource.active), '[]'::jsonb);
end;
$$;
