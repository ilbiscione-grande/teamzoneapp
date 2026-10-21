-- Bokningshanterare: several resources at once (two locker rooms, a pitch and
-- a camera for the same time). All of them are booked or none; each keeps
-- its own approval rule. The bookings share a group id, so the group can be
-- approved or cancelled together. Admins get one request for the group.

alter table core.booking_bookings add column group_id uuid;
create index booking_bookings_group on core.booking_bookings (group_id) where group_id is not null;

-- As in 20261117090000, with the group the booking belongs to.
create or replace function internal.booking_json(booking core.booking_bookings, actor_role text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', booking.id, 'resource_id', booking.resource_id,
    'resource_name', (select resource.name from core.booking_resources resource where resource.id = booking.resource_id),
    'starts_at', booking.starts_at, 'ends_at', booking.ends_at,
    'title', booking.title, 'notes', booking.notes, 'status', booking.status,
    'booked_by_name', internal.booking_person_name(booking.booked_by),
    'is_mine', booking.booked_by = auth.uid(),
    'team_id', booking.team_id,
    'team_name', (select team.name from core.teams team where team.id = booking.team_id),
    'event_id', booking.event_id,
    'event_title', (select event_row.title from core.events event_row where event_row.id = booking.event_id),
    'series_id', booking.series_id,
    'series_remaining', case when booking.series_id is null then null else (select count(*) from core.booking_bookings other
      where other.series_id = booking.series_id and other.status in ('pending', 'confirmed') and other.ends_at > now()) end,
    'group_id', booking.group_id,
    'group_resources', case when booking.group_id is null then null else (select jsonb_agg(resource.name order by resource.name)
      from core.booking_bookings other join core.booking_resources resource on resource.id = other.resource_id
      where other.group_id = booking.group_id and other.status in ('pending', 'confirmed')) end,
    'can_cancel', booking.status in ('pending', 'confirmed') and booking.ends_at > now()
      and (booking.booked_by = auth.uid() or actor_role = 'admin'),
    'can_decide', booking.status = 'pending' and actor_role = 'admin' and booking.ends_at > now()
  )
$$;

-- Checks (dry run) or books several resources for one time. Every resource
-- says whether it is free; without a dry run all are booked, or none.
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
  if target_team_id is not null and not exists (
    select 1 from internal.booking_actor_teams(organization) t where t.team_id = target_team_id) then
    raise insufficient_privilege using message = 'not_team_leader';
  end if;
  if target_event_id is not null then
    if target_team_id is null then raise invalid_parameter_value using message = 'event_needs_team'; end if;
    if not exists (select 1 from core.events where id = target_event_id) or not internal.actor_can_read_event(target_event_id)
      or not exists (select 1 from core.event_teams relation where relation.event_id = target_event_id and relation.team_id = target_team_id) then
      raise insufficient_privilege using message = 'event_not_found';
    end if;
  end if;
  -- Locks in a fixed order, so two groups cannot wait for each other.
  perform pg_advisory_xact_lock(hashtextextended(value::text, 0))
  from unnest(target_resource_ids) value order by value;
  for resource in select * from core.booking_resources where id = any(target_resource_ids) order by category, name loop
    busy := not resource.active or exists (select 1 from core.booking_bookings other
      where other.resource_id = resource.id and other.status in ('pending', 'confirmed')
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

-- Approves or declines the group's waiting bookings at once.
create or replace function internal.decide_booking_group_for_actor(target_group_id uuid, approve boolean)
returns integer language plpgsql security definer set search_path = '' as $$
declare first_booking core.booking_bookings; changed integer;
begin
  select * into first_booking from core.booking_bookings
  where group_id = target_group_id and status = 'pending' and ends_at > now() order by created_at limit 1;
  if first_booking.id is null then raise invalid_parameter_value using message = 'not_pending'; end if;
  if internal.booking_actor_role(first_booking.organization_id) is distinct from 'admin' then
    raise insufficient_privilege using message = 'not_admin';
  end if;
  update core.booking_bookings set status = case when approve then 'confirmed' else 'declined' end,
    decided_by = auth.uid(), decided_at = now(), revision = revision + 1
  where group_id = target_group_id and status = 'pending' and ends_at > now();
  get diagnostics changed = row_count;
  perform internal.booking_notify(first_booking.id, case when approve then 'approved' else 'declined' end, array[first_booking.booked_by]);
  return changed;
end;
$$;

-- Cancels the whole group (the one who booked, or an admin).
create or replace function internal.cancel_booking_group_for_actor(target_group_id uuid)
returns integer language plpgsql security definer set search_path = '' as $$
declare first_booking core.booking_bookings; changed integer;
begin
  select * into first_booking from core.booking_bookings
  where group_id = target_group_id and status in ('pending', 'confirmed') and ends_at > now() order by created_at limit 1;
  if first_booking.id is null or internal.booking_actor_role(first_booking.organization_id) is null then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if first_booking.booked_by <> auth.uid() and internal.booking_actor_role(first_booking.organization_id) <> 'admin' then
    raise insufficient_privilege using message = 'not_allowed';
  end if;
  update core.booking_bookings set status = 'cancelled', revision = revision + 1
  where group_id = target_group_id and status in ('pending', 'confirmed') and ends_at > now();
  get diagnostics changed = row_count;
  if first_booking.booked_by <> auth.uid() then
    perform internal.booking_notify(first_booking.id, 'cancelled', array[first_booking.booked_by]);
  end if;
  return changed;
end;
$$;

create or replace function api.create_booking_group(
  target_resource_ids uuid[], booking_starts_at timestamptz, booking_ends_at timestamptz,
  booking_title text, booking_notes text, target_team_id uuid, target_event_id uuid, dry_run boolean
) returns jsonb language sql security invoker set search_path = '' as
$$ select internal.create_booking_group_for_actor(target_resource_ids, booking_starts_at, booking_ends_at, booking_title,
  booking_notes, target_team_id, target_event_id, dry_run) $$;
create or replace function api.decide_booking_group(target_group_id uuid, approve boolean) returns integer language sql security invoker set search_path = '' as
$$ select internal.decide_booking_group_for_actor(target_group_id, approve) $$;
create or replace function api.cancel_booking_group(target_group_id uuid) returns integer language sql security invoker set search_path = '' as
$$ select internal.cancel_booking_group_for_actor(target_group_id) $$;

revoke all on function
  internal.create_booking_group_for_actor(uuid[], timestamptz, timestamptz, text, text, uuid, uuid, boolean),
  internal.decide_booking_group_for_actor(uuid, boolean), internal.cancel_booking_group_for_actor(uuid),
  api.create_booking_group(uuid[], timestamptz, timestamptz, text, text, uuid, uuid, boolean),
  api.decide_booking_group(uuid, boolean), api.cancel_booking_group(uuid)
from public, anon, authenticated;
grant execute on function
  internal.create_booking_group_for_actor(uuid[], timestamptz, timestamptz, text, text, uuid, uuid, boolean),
  internal.decide_booking_group_for_actor(uuid, boolean), internal.cancel_booking_group_for_actor(uuid),
  api.create_booking_group(uuid[], timestamptz, timestamptz, text, text, uuid, uuid, boolean),
  api.decide_booking_group(uuid, boolean), api.cancel_booking_group(uuid)
to authenticated;
