import { bookingSpan } from "../../lib/booking";
import type { BookingRequest } from "../../lib/booking-requests";

/** A complete pending decision, shown before its existing approve/decline actions. */
export function RequestReview({ request }: { request: BookingRequest }) {
  const resources = [...new Set(request.pending.map(booking => booking.resource_name))];
  const dates = [...new Set(request.pending.map(booking => new Date(booking.starts_at).toLocaleDateString("sv-SE")))];
  return <div className="bk-request-review">
    <p><strong>{request.kind === "series" ? "Beslutet gäller alla väntande tillfällen i serien." : request.kind === "group" ? "Beslutet gäller alla väntande resurser i gruppen." : "Beslutet gäller den här bokningen."}</strong></p>
    <dl className="wt-facts">
      <dt>Väntande</dt><dd>{request.pending.length} {request.pending.length === 1 ? "resursbokning" : "resursbokningar"}</dd>
      <dt>Resurser</dt><dd>{resources.join(", ")}</dd>
      <dt>Datum</dt><dd>{dates.length === 1 ? dates[0] : `${dates[0]}–${dates[dates.length-1]} · ${dates.length} datum`}</dd>
    </dl>
    <details className="bk-resource-details"><summary>Visa alla som ingår ({request.pending.length})</summary>
      <ul className="bk-request-items">{request.pending.map(booking => <li key={booking.id}>
        <strong>{booking.resource_name}</strong>
        <span>{new Date(booking.starts_at).toLocaleDateString("sv-SE",{weekday:"short",day:"numeric",month:"short",year:"numeric"})} · {bookingSpan(booking.starts_at,booking.ends_at)}{new Date(booking.ends_at).toLocaleDateString("sv-SE") !== new Date(booking.starts_at).toLocaleDateString("sv-SE") ? ` (slutar ${new Date(booking.ends_at).toLocaleDateString("sv-SE")})` : ""}</span>
        {booking.notes && <span>Anteckning: {booking.notes}</span>}
      </li>)}</ul>
    </details>
    <p className="wt-small">Redan bekräftade bokningar lämnas kvar. Uppgifterna och din behörighet kontrolleras igen när beslutet sparas.</p>
  </div>;
}
