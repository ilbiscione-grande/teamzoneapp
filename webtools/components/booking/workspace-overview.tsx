"use client";

import { useCallback, useEffect, useState } from "react";
import { addDays, bookingError, dateKey, localInstant, type Booking, type Organization } from "../../lib/booking";
import { upcomingBookings, upcomingBookingGroups } from "../../lib/booking-workspace";
import { useAccount } from "../account";
import { SeriesAttention } from './series-attention';
import { BookingCard } from './booking-card';

export function WorkspaceOverview({ org, pending, onCalendar, onAvailability, onOpen, onSeries }: {
  org: Organization;
  pending?: React.ReactNode;
  onCalendar: () => void;
  onAvailability: () => void;
  onOpen: (booking: Booking) => void;
  onSeries: (bookingId:string|null) => void;
}) {
  const { client } = useAccount();
  const [bookings, setBookings] = useState<Booking[] | null>(null);
  const [error, setError] = useState("");
  const load = useCallback(async () => {
    if (!client) return;
    setError("");
    const now = new Date();
    const { data, error: loadError } = await client.schema("api").rpc("list_bookings", {
      target_organization_id: org.id,
      range_start: now.toISOString(),
      range_end: localInstant(addDays(dateKey(now), 7), "00:00"),
    });
    if (loadError) { setError(bookingError(loadError)); return; }
    setBookings(upcomingBookings((data ?? []) as Booking[], org.role !== "admin", now.getTime()));
  }, [client, org.id, org.role]);
  useEffect(() => { void load(); }, [load]);
  const groups=upcomingBookingGroups(bookings??[],org.resources);
  return (
    <section className="bk-overview" aria-label="Bokningsöversikt">
      <div className="bk-workspace-title">
        <h2>{org.role === "admin" ? "Din bokningsöversikt" : "Boka och planera"}</h2>
        <p className="wt-small">{org.role === "admin" ? "Hantera förfrågningar och håll koll på kommande bokningar." : "Hitta en ledig tid och följ dina bokningar."}</p>
      </div>
      {pending}
      {org.role==='admin' && <SeriesAttention organizationId={org.id} resources={org.resources} onOpen={onSeries}/>}
      <section className="wt-panel">
        <div className="bk-panel-heading"><h3>{org.role === "admin" ? "Kommande bokningar" : "Mina kommande bokningar"}</h3><button className="wt-button secondary small" onClick={onCalendar}>Öppna kalendern</button></div>
        <p className="wt-small">Från nu och de närmaste sju dagarna. Alla tider visas i din lokala tidszon.</p>
        {error ? <div><p className="wt-error" role="alert">{error}</p><button className="wt-button secondary small" onClick={() => void load()}>Försök igen</button></div>
          : bookings === null ? <p role="status">Laddar bokningar…</p>
          : bookings.length === 0 ? <p>Inga kommande bokningar under den här perioden.</p>
          : <ul className="bk-bookings">{groups.slice(0, 6).map(({key,booking,items,resourceLabel}) => (
            <BookingCard key={key} booking={booking} resourceLabel={resourceLabel} resourceCount={items.length} onOpen={onOpen} showDate />
          ))}</ul>}
        {bookings && groups.length > 6 && <p className="wt-small">Visar de sex första bokningarna. Se övriga i kalendern.</p>}
      </section>
      <section className="wt-panel bk-availability-shortcut"><div><h3>Hitta en ledig tid</h3><p className="wt-small">Jämför resurser och se vad som går att boka vid en viss tid.</p></div><button className="wt-button secondary" onClick={onAvailability}>Visa tillgänglighet</button></section>
    </section>
  );
}
