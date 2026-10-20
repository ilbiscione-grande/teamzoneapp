"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import {
  addDays, bookingError, bookingSpan, categoryLabels, dateKey, dayLabel, dayRange, groupResources, kindLabels, statusLabels,
  type Booking, type Organization, type Resource,
} from "../../lib/booking";
import { useAccount } from "../account";
import { BookingForm } from "./booking-form";
import { ResourcesAdmin, SettingsAdmin } from "./admin";

type Tab = "calendar" | "mine" | "pending" | "resources" | "settings";

export function BookingOrganization({ id }: { id: string }) {
  const { client } = useAccount();
  const [org, setOrg] = useState<Organization | null>(null);
  const [error, setError] = useState("");
  const [tab, setTab] = useState<Tab>("calendar");

  const load = useCallback(async () => {
    if (!client) return;
    const { data, error: loadError } = await client.schema("api").rpc("get_booking_organization", { target_organization_id: id });
    if (loadError) { setError(bookingError(loadError)); return; }
    setOrg(data as Organization);
  }, [client, id]);

  useEffect(() => { void load(); }, [load]);

  if (error) return <section className="wt-panel"><p role="alert" className="wt-error">{error}</p><Link className="wt-link" href="/bokningar">Till dina organisationer</Link></section>;
  if (!org) return <p className="wt-status">Laddar…</p>;
  const admin = org.role === "admin";
  const tabs: [Tab, string][] = [
    ["calendar", "Kalender"],
    ["mine", "Mina bokningar"],
    ...(admin ? [["pending", org.pending_count ? `Att godkänna (${org.pending_count})` : "Att godkänna"], ["resources", "Resurser"], ["settings", "Inställningar"]] as [Tab, string][] : []),
  ];
  return (
    <div className="bk-org">
      <div className="bk-org-head">
        <div>
          <h1>{org.name}</h1>
          <p className="wt-small">
            {[kindLabels[org.kind], org.sport, org.teamzone_club_name ? `Kopplad till ${org.teamzone_club_name} i TeamZone` : null].filter(Boolean).join(" · ")}
          </p>
        </div>
        <Link className="wt-link" href="/bokningar">Byt organisation</Link>
      </div>
      <div className="bk-tabs" role="tablist" aria-label="Bokningar">
        {tabs.map(([value, label]) => (
          <button key={value} type="button" role="tab" aria-selected={tab === value} onClick={() => setTab(value)}>{label}</button>
        ))}
      </div>
      {tab === "calendar" && <DayView org={org} />}
      {tab === "mine" && <MyBookings org={org} />}
      {tab === "pending" && admin && <Pending org={org} onChanged={load} />}
      {tab === "resources" && admin && <ResourcesAdmin org={org} onChanged={load} />}
      {tab === "settings" && admin && <SettingsAdmin org={org} onChanged={load} />}
    </div>
  );
}

function BookingRow({ booking, onChanged, showResource = false, showDate = false }: { booking: Booking; onChanged: () => void; showResource?: boolean; showDate?: boolean }) {
  const { client } = useAccount();
  const [error, setError] = useState("");
  const act = async (name: "cancel_booking" | "decide_booking", approve?: boolean) => {
    if (!client) return;
    if (name === "cancel_booking" && !window.confirm("Avboka den här bokningen?")) return;
    const { error: actError } = await client.schema("api").rpc(name, name === "cancel_booking"
      ? { target_booking_id: booking.id } : { target_booking_id: booking.id, approve });
    if (actError) { setError(bookingError(actError)); return; }
    onChanged();
  };
  return (
    <li className="bk-booking" data-status={booking.status}>
      <div className="bk-booking-time">
        {showDate && <span>{new Date(booking.starts_at).toLocaleDateString("sv-SE", { weekday: "short", day: "numeric", month: "short" })}</span>}
        <strong>{bookingSpan(booking.starts_at, booking.ends_at)}</strong>
      </div>
      <div className="bk-booking-body">
        <strong>{[showResource ? booking.resource_name : null, booking.title].filter(Boolean).join(" · ") || "Bokad"}</strong>
        <span>{[booking.team_name, booking.event_title ? `till ${booking.event_title}` : null, booking.is_mine ? "Du" : booking.booked_by_name].filter(Boolean).join(" · ")}</span>
        {booking.status === "pending" && <span className="bk-badge">{statusLabels.pending}</span>}
        {error && <span role="alert" className="wt-error">{error}</span>}
      </div>
      <div className="bk-booking-actions">
        {booking.can_decide && <button type="button" className="wt-button small" onClick={() => act("decide_booking", true)}>Godkänn</button>}
        {booking.can_decide && <button type="button" className="wt-button secondary small" onClick={() => act("decide_booking", false)}>Neka</button>}
        {booking.can_cancel && !booking.can_decide && <button type="button" className="wt-button secondary small" onClick={() => act("cancel_booking")}>Avboka</button>}
      </div>
    </li>
  );
}

function DayView({ org }: { org: Organization }) {
  const { client } = useAccount();
  const [day, setDay] = useState(() => dateKey(new Date()));
  const [bookings, setBookings] = useState<Booking[] | null>(null);
  const [booking, setBooking] = useState<Resource | null>(null);
  const [notice, setNotice] = useState("");
  const [error, setError] = useState("");

  const load = useCallback(async () => {
    if (!client) return;
    setBookings(null);
    const { from, to } = dayRange(day);
    const { data, error: loadError } = await client.schema("api").rpc("list_bookings", { target_organization_id: org.id, range_start: from, range_end: to });
    if (loadError) { setError(bookingError(loadError)); setBookings([]); return; }
    setError("");
    setBookings(data as Booking[]);
  }, [client, org.id, day]);

  useEffect(() => { void load(); }, [load]);

  const groups = groupResources(org.resources);
  return (
    <section aria-label="Kalender">
      <div className="bk-day-nav">
        <button type="button" className="wt-button secondary small" onClick={() => setDay(addDays(day, -1))} aria-label="Föregående dag">‹</button>
        <label className="bk-day-picker">
          <span>{dayLabel(day)}</span>
          <input type="date" value={day} onChange={event => event.target.value && setDay(event.target.value)} aria-label="Välj dag" />
        </label>
        <button type="button" className="wt-button secondary small" onClick={() => setDay(addDays(day, 1))} aria-label="Nästa dag">›</button>
        {day !== dateKey(new Date()) && <button type="button" className="wt-link-button" onClick={() => setDay(dateKey(new Date()))}>Idag</button>}
      </div>
      {notice && <p className="wt-note" role="status">{notice}</p>}
      {error && <p className="wt-error" role="alert">{error}</p>}
      {groups.length === 0 ? (
        <div className="wt-panel">
          <p>Det finns inga resurser att boka än.</p>
          {org.role === "admin" && <p className="wt-small">Lägg upp planer, lokaler, fordon eller utrustning under Resurser.</p>}
        </div>
      ) : groups.map(group => (
        <div key={group.category} className="bk-group">
          <h2>{categoryLabels[group.category]}</h2>
          {group.items.map(resource => {
            const own = (bookings ?? []).filter(item => item.resource_id === resource.id);
            return (
              <article key={resource.id} className="bk-resource">
                <header>
                  <div>
                    <h3>{resource.name}</h3>
                    <p className="wt-small">{[resource.location, resource.capacity ? `${resource.capacity} platser` : null, resource.requires_approval ? "Kräver godkännande" : null].filter(Boolean).join(" · ")}</p>
                  </div>
                  <button type="button" className="wt-button small" onClick={() => { setNotice(""); setBooking(resource); }}>Boka</button>
                </header>
                {bookings === null ? <p className="wt-small">Laddar…</p> : own.length === 0 ? <p className="wt-small">Ledig hela dagen.</p> : (
                  <ul className="bk-bookings">{own.map(item => <BookingRow key={item.id} booking={item} onChanged={load} />)}</ul>
                )}
              </article>
            );
          })}
        </div>
      ))}
      {booking && (
        <BookingForm org={org} resource={booking} day={day} onClose={() => setBooking(null)} onBooked={status => {
          setBooking(null);
          setNotice(status === "pending" ? "Förfrågan är skickad. Den visas som väntande tills en administratör har godkänt den." : "Bokningen är klar.");
          void load();
        }} />
      )}
    </section>
  );
}

/** Your coming bookings in the next two months. */
function MyBookings({ org }: { org: Organization }) {
  const { client } = useAccount();
  const [bookings, setBookings] = useState<Booking[] | null>(null);
  const [error, setError] = useState("");
  const load = useCallback(async () => {
    if (!client) return;
    const from = new Date();
    const to = new Date(from.getTime() + 60 * 86400e3);
    const { data, error: loadError } = await client.schema("api").rpc("list_bookings", { target_organization_id: org.id, range_start: from.toISOString(), range_end: to.toISOString() });
    if (loadError) { setError(bookingError(loadError)); return; }
    setBookings((data as Booking[]).filter(item => item.is_mine));
  }, [client, org.id]);
  useEffect(() => { void load(); }, [load]);
  if (error) return <p className="wt-error" role="alert">{error}</p>;
  if (!bookings) return <p className="wt-status">Laddar…</p>;
  return (
    <section className="wt-panel" aria-label="Mina bokningar">
      {bookings.length === 0 ? <p>Du har inga kommande bokningar de närmaste två månaderna.</p> : (
        <ul className="bk-bookings">{bookings.map(item => <BookingRow key={item.id} booking={item} onChanged={load} showResource showDate />)}</ul>
      )}
    </section>
  );
}

function Pending({ org, onChanged }: { org: Organization; onChanged: () => void }) {
  const { client } = useAccount();
  const [bookings, setBookings] = useState<Booking[] | null>(null);
  const [error, setError] = useState("");
  const load = useCallback(async () => {
    if (!client) return;
    const { data, error: loadError } = await client.schema("api").rpc("list_pending_bookings", { target_organization_id: org.id });
    if (loadError) { setError(bookingError(loadError)); return; }
    setBookings(data as Booking[]);
  }, [client, org.id]);
  useEffect(() => { void load(); }, [load]);
  if (error) return <p className="wt-error" role="alert">{error}</p>;
  if (!bookings) return <p className="wt-status">Laddar…</p>;
  return (
    <section className="wt-panel" aria-label="Att godkänna">
      {bookings.length === 0 ? <p>Inga förfrågningar väntar på godkännande.</p> : (
        <ul className="bk-bookings">{bookings.map(item => <BookingRow key={item.id} booking={item} onChanged={() => { void load(); onChanged(); }} showResource showDate />)}</ul>
      )}
    </section>
  );
}
