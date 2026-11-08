import type { Booking } from "./booking.ts";

export type RequestKind = "single" | "group" | "series";
export type BookingRequest = { key: string; kind: RequestKind; booking: Booking; pending: Booking[] };
export const requestKindLabels: Record<RequestKind, string> = {single:"En bokning",group:"Flera resurser",series:"Återkommande serie"};

/** Keep each server decision whole, including when searching a non-leading resource or occurrence. */
export function bookingRequests(bookings: Booking[]): BookingRequest[] {
  const groups = new Map<string, BookingRequest>();
  const sorted = bookings.filter(booking => booking.status === "pending").slice().sort((a,b) => Date.parse(a.starts_at) - Date.parse(b.starts_at) || a.id.localeCompare(b.id));
  for (const booking of sorted) {
    const kind: RequestKind = booking.series_id ? "series" : booking.group_id ? "group" : "single";
    const key = `${kind}:${booking.series_id || booking.group_id || booking.id}`;
    const group = groups.get(key);
    if (group) group.pending.push(booking);
    else groups.set(key, {key,kind,booking,pending:[booking]});
  }
  return [...groups.values()];
}

export function filterBookingRequests(requests: BookingRequest[], query: string, kind: RequestKind | "all"): BookingRequest[] {
  const words = query.trim().toLocaleLowerCase("sv").split(/\s+/).filter(Boolean);
  return requests.filter(request => {
    if (kind !== "all" && request.kind !== kind) return false;
    const text = request.pending.flatMap(booking => [booking.title,booking.resource_name,booking.team_name,booking.event_title,booking.booked_by_name,booking.notes,booking.starts_at.slice(0,10)]).filter(Boolean).join(" ").toLocaleLowerCase("sv");
    return words.every(word => text.includes(word));
  });
}
