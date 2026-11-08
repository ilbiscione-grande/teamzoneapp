import type { Booking, Resource } from "./booking.ts";
import { seriesScopeLabel } from './series-alternatives.ts';

/** Group one occurrence only when its identity, timing, status and permissions agree. */
export function upcomingBookingGroups(bookings:Booking[],resources:Resource[]):{key:string;booking:Booking;items:Booking[];resourceLabel:string}[] {
  const groups=new Map<string,Booking[]>();const seen=new Set<string>();
  for(const booking of [...bookings].sort((a,b)=>Date.parse(a.starts_at)-Date.parse(b.starts_at)||a.id.localeCompare(b.id))) {
    if(seen.has(booking.id))continue;seen.add(booking.id);
    const key=booking.group_id ? JSON.stringify(['group',booking.group_id,booking.starts_at,booking.ends_at,booking.status,
      booking.series_id,booking.title,booking.notes,booking.team_id,booking.event_id,booking.is_mine,booking.booked_by_name,
      booking.can_cancel,booking.can_decide,!!booking.can_move_event]) : JSON.stringify(['booking',booking.id]);
    groups.set(key,[...(groups.get(key)??[]),booking]);
  }
  return [...groups].map(([key,items])=>{
    const ids=[...new Set(items.map(item=>item.resource_id))];
    const resourceLabel=ids.every(id=>resources.some(resource=>resource.id===id)) ? seriesScopeLabel(ids,resources) : [...new Set(items.map(item=>item.resource_name))].join(', ');
    return {key,booking:items[0],items,resourceLabel};
  });
}

/** A series is decided as a whole; otherwise resources booked together share a decision. */
export function bookingDecisions(bookings: Booking[]): Booking[] {
  const seen = new Set<string>();
  return bookings.filter(booking => {
    const key = booking.series_id ? `series:${booking.series_id}`
      : booking.group_id ? `group:${booking.group_id}` : `booking:${booking.id}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

export function upcomingBookings(bookings: Booking[], ownOnly: boolean, now: number): Booking[] {
  return bookings.filter(booking =>
    (!ownOnly || booking.is_mine) &&
    (booking.status === "confirmed" || booking.status === "pending") &&
    new Date(booking.ends_at).getTime() > now)
    .sort((a, b) => Date.parse(a.starts_at) - Date.parse(b.starts_at) || a.id.localeCompare(b.id));
}
