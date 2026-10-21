-- Bokningshanterare in the app: an activity's bookings can be cancelled
-- there. Besides the booker and the organisation's admins, a leader of the
-- team a booking is for may cancel it.
create or replace function internal.booking_actor_leads_team(target_organization_id uuid, target_team_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select target_team_id is not null and exists (
    select 1 from internal.booking_actor_teams(target_organization_id) t where t.team_id = target_team_id)
$$;

create or replace function internal.booking_actor_can_cancel(booking core.booking_bookings)
returns boolean language sql stable security definer set search_path = '' as $$
  select booking.status in ('pending', 'confirmed') and booking.ends_at > now()
    and (booking.booked_by = auth.uid()
      or internal.booking_actor_role(booking.organization_id) = 'admin'
      or internal.booking_actor_leads_team(booking.organization_id, booking.team_id))
$$;

-- As in 20261117100000, with team leaders allowed to cancel.
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
    'can_cancel', internal.booking_actor_can_cancel(booking),
    'can_decide', booking.status = 'pending' and actor_role = 'admin' and booking.ends_at > now()
  )
$$;

-- As in 20261115090000, with what you may do with each booking.
create or replace function internal.list_event_bookings_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not internal.actor_can_read_event(target_event_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', booking.id, 'resource_name', resource.name, 'category', resource.category,
      'organization_name', org.name, 'starts_at', booking.starts_at, 'ends_at', booking.ends_at,
      'status', booking.status, 'title', booking.title, 'group_id', booking.group_id,
      'can_cancel', internal.booking_actor_can_cancel(booking)
    ) order by booking.starts_at, resource.name)
    from core.booking_bookings booking
    join core.booking_resources resource on resource.id = booking.resource_id
    join core.booking_organizations org on org.id = booking.organization_id
    where booking.event_id = target_event_id and booking.status in ('pending', 'confirmed')), '[]'::jsonb);
end;
$$;

-- As in 20261116090000, with team leaders allowed.
create or replace function internal.cancel_booking_for_actor(target_booking_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare booking core.booking_bookings;
begin
  select * into booking from core.booking_bookings where id = target_booking_id;
  if booking.id is null or (internal.booking_actor_role(booking.organization_id) is null
    and not internal.booking_actor_leads_team(booking.organization_id, booking.team_id)) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if booking.status not in ('pending', 'confirmed') then raise invalid_parameter_value using message = 'not_active'; end if;
  if not internal.booking_actor_can_cancel(booking) then
    raise insufficient_privilege using message = 'not_allowed';
  end if;
  update core.booking_bookings set status = 'cancelled', revision = revision + 1 where id = target_booking_id;
  if booking.booked_by <> auth.uid() then
    perform internal.booking_notify(booking.id, 'cancelled', array[booking.booked_by]);
  end if;
end;
$$;

-- As in 20261117100000, with team leaders allowed.
create or replace function internal.cancel_booking_group_for_actor(target_group_id uuid)
returns integer language plpgsql security definer set search_path = '' as $$
declare first_booking core.booking_bookings; changed integer;
begin
  select * into first_booking from core.booking_bookings
  where group_id = target_group_id and status in ('pending', 'confirmed') and ends_at > now() order by created_at limit 1;
  if first_booking.id is null or (internal.booking_actor_role(first_booking.organization_id) is null
    and not internal.booking_actor_leads_team(first_booking.organization_id, first_booking.team_id)) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if not internal.booking_actor_can_cancel(first_booking) then
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

revoke all on function internal.booking_actor_leads_team(uuid, uuid),
  internal.booking_actor_can_cancel(core.booking_bookings) from public, anon, authenticated;
grant execute on function internal.booking_actor_leads_team(uuid, uuid),
  internal.booking_actor_can_cancel(core.booking_bookings) to authenticated;
