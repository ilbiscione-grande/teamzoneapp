import { gridPlacement, matchesFilter, resourcePath, type Booking, type CalendarFilter, type Resource } from "./booking.ts";

/** ISO week: the Thursday determines the week-year, including year boundaries. */
export function calendarWeek(key: string): number {
  const [year, month, day] = key.split("-").map(Number);
  const thursday = new Date(Date.UTC(year, month - 1, day));
  thursday.setUTCDate(thursday.getUTCDate() + 4 - (thursday.getUTCDay() || 7));
  const yearStart = Date.UTC(thursday.getUTCFullYear(), 0, 1);
  return Math.ceil(((thursday.getTime() - yearStart) / 86400e3 + 1) / 7);
}

/** One resource booking per row; overnight bookings appear on every day they occupy. */
export function bookingAgenda(bookings: Booking[], resources: Resource[], days: string[], filter: CalendarFilter, query: string): { day: string; bookings: Booking[] }[] {
  const paths = new Map(resources.filter(resource => resource.active).map(resource => [resource.id, resourcePath(resource, resources)]));
  const words = query.trim().toLocaleLowerCase("sv").split(/\s+/).filter(Boolean);
  const matching = bookings.filter(booking => {
    if (!paths.has(booking.resource_id) || (filter.resourceIds !== null && !filter.resourceIds.includes(booking.resource_id)) || !matchesFilter(booking, filter)) return false;
    const text = [booking.title, booking.resource_name, paths.get(booking.resource_id), booking.team_name, booking.event_title, booking.booked_by_name].filter(Boolean).join(" ").toLocaleLowerCase("sv");
    return words.every(word => text.includes(word));
  }).sort((a, b) => Date.parse(a.starts_at) - Date.parse(b.starts_at) || a.resource_name.localeCompare(b.resource_name, "sv") || a.id.localeCompare(b.id));
  return days.map(day => ({ day, bookings: matching.filter(booking => gridPlacement(booking.starts_at, booking.ends_at, day, filter.range) !== null) })).filter(group => group.bookings.length > 0);
}
