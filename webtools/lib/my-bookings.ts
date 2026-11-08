import { dateKey, type Booking, type Resource } from "./booking.ts";
import { upcomingBookingGroups } from "./booking-workspace.ts";

/** Search across a complete shared booking, preserving all its resources. */
export function myBookingEntries(bookings: Booking[], resources: Resource[], query: string, status: MyBookingStatus, days: number, now: number) {
  const active = myBookingGroups(bookings, "", status, days, now).flatMap(day => day.bookings);
  const words = query.trim().toLocaleLowerCase("sv").split(/\s+/).filter(Boolean);
  const entries = upcomingBookingGroups(active, resources).filter(entry => {
    const text = [entry.resourceLabel, ...entry.items.flatMap(item => [item.title, item.resource_name, item.team_name, item.event_title, item.notes])].filter(Boolean).join(" ").toLocaleLowerCase("sv");
    return words.every(word => text.includes(word));
  });
  const groups = new Map<string, typeof entries>();
  for (const entry of entries) {
    const day = dateKey(new Date(entry.booking.starts_at));
    groups.set(day, [...(groups.get(day) ?? []), entry]);
  }
  return [...groups].map(([day, entries]) => ({ day, entries }));
}

export type MyBookingStatus = "all" | "confirmed" | "pending";
export function myBookingGroups(bookings: Booking[], query: string, status: MyBookingStatus, days: number, now: number): { day: string; bookings: Booking[] }[] {
  const until = now + days * 86400e3;
  const words = query.trim().toLocaleLowerCase("sv").split(/\s+/).filter(Boolean);
  const matching = bookings.filter(booking => {
    if (!booking.is_mine || !["pending","confirmed"].includes(booking.status) || Date.parse(booking.ends_at) <= now || Date.parse(booking.starts_at) >= until) return false;
    if (status !== "all" && booking.status !== status) return false;
    const text = [booking.title,booking.resource_name,booking.team_name,booking.event_title,booking.notes].filter(Boolean).join(" ").toLocaleLowerCase("sv");
    return words.every(word => text.includes(word));
  }).sort((a,b) => Date.parse(a.starts_at)-Date.parse(b.starts_at) || a.resource_name.localeCompare(b.resource_name,"sv") || a.id.localeCompare(b.id));
  const groups = new Map<string, Booking[]>();
  for (const booking of matching) {
    const day = dateKey(new Date(booking.starts_at));
    groups.set(day,[...(groups.get(day) ?? []),booking]);
  }
  return [...groups].map(([day,bookings]) => ({day,bookings}));
}
