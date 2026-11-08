"use client";

import { bookingSpan, statusLabels, type Booking } from "../../lib/booking";

/** One native button makes the complete booking row a keyboard and touch target. */
export function BookingCard({ booking, resourceLabel, resourceCount, onOpen, showDate = false, showOwner = false }: {
  booking: Booking; resourceLabel: string; resourceCount: number;
  onOpen: (booking: Booking) => void; showDate?: boolean; showOwner?: boolean;
}) {
  const date = new Date(booking.starts_at).toLocaleDateString("sv-SE", { weekday: "short", day: "numeric", month: "short" });
  const description = [booking.title ? resourceLabel : null, booking.team_name,
    showOwner && booking.event_title ? `till ${booking.event_title}` : null,
    showOwner ? booking.is_mine ? "Du" : booking.booked_by_name : null].filter(Boolean).join(" · ");
  return <li>
    <button type="button" className="bk-booking bk-booking-card" data-status={booking.status} onClick={() => onOpen(booking)}>
      <span className="bk-booking-time"><span className={showDate ? undefined : "bk-card-date-hidden"}>{date}</span><strong>{bookingSpan(booking.starts_at, booking.ends_at)}</strong></span>
      <span className="bk-booking-body">
        <strong>{booking.title || resourceLabel}</strong>
        {description && <span>{description}</span>}
        <span className="bk-badge">{statusLabels[booking.status]}{resourceCount > 1 ? ` · ${resourceCount} resurser` : ""}</span>
        {booking.series_id && <span>Återkommande{showOwner && booking.series_remaining != null ? ` · ${booking.series_remaining} kommande tillfällen` : ""}</span>}
      </span>
      <span className="bk-booking-card-action">Öppna bokning <span aria-hidden="true">→</span></span>
    </button>
  </li>;
}
