-- Bokningshanterare in the app: every active resource of an organisation for
-- a time, and whether it is free; when not, what it is booked for.
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
      'busy', clash.id is not null,
      'busy_with', case when clash.id is null then null else coalesce(
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

create or replace function api.list_booking_availability(target_organization_id uuid, range_start timestamptz, range_end timestamptz)
returns jsonb language sql stable security invoker set search_path = '' as
$$ select internal.list_booking_availability_for_actor(target_organization_id, range_start, range_end) $$;

revoke all on function internal.list_booking_availability_for_actor(uuid, timestamptz, timestamptz),
  api.list_booking_availability(uuid, timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function internal.list_booking_availability_for_actor(uuid, timestamptz, timestamptz),
  api.list_booking_availability(uuid, timestamptz, timestamptz) to authenticated;
