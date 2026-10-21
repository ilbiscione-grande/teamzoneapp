-- Bokningshanterare in TeamZone's assistant: the organisations where you
-- approve bookings and how many requests wait, whatever your TeamZone role.
create or replace function internal.list_my_booking_approvals_for_actor()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'organization_id', org.id, 'name', org.name, 'teamzone_club_id', org.teamzone_club_id,
    'pending', waiting.pending, 'first_starts_at', waiting.first_starts_at
  ) order by waiting.first_starts_at), '[]'::jsonb)
  from core.booking_organizations org
  join lateral (
    select count(*) pending, min(booking.starts_at) first_starts_at
    from core.booking_bookings booking
    where booking.organization_id = org.id and booking.status = 'pending' and booking.ends_at > now()
  ) waiting on waiting.pending > 0
  where internal.booking_actor_role(org.id) = 'admin'
$$;

create or replace function api.list_my_booking_approvals() returns jsonb language sql stable security invoker set search_path = '' as
$$ select internal.list_my_booking_approvals_for_actor() $$;

revoke all on function internal.list_my_booking_approvals_for_actor(), api.list_my_booking_approvals() from public, anon, authenticated;
grant execute on function internal.list_my_booking_approvals_for_actor(), api.list_my_booking_approvals() to authenticated;
