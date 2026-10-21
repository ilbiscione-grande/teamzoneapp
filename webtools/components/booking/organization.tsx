"use client";

import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { bookingError, bookingSpan, kindLabels, statusLabels, type Booking, type Organization } from "../../lib/booking";
import { useAccount } from "../account";
import { BookingCalendar } from "./calendar";
import { ResourcesAdmin, SettingsAdmin } from "./admin";

type Tab = "calendar" | "mine" | "pending" | "resources" | "settings";

export function BookingOrganization({ id }: { id: string }) {
  const { client } = useAccount();
  const [org, setOrg] = useState<Organization | null>(null);
  const [error, setError] = useState("");
  const [tab, setTab] = useState<Tab>("calendar");
  const params = useSearchParams();
  const router = useRouter();
  const path = usePathname();
  // From the app: ?boka=1&lag=<team>&aktivitet=<event>.
  const uuid = /^[0-9a-f-]{36}$/;
  const eventParam = params.get("aktivitet");
  const teamParam = params.get("lag");
  const prefill = params.get("boka") === "1" && eventParam && uuid.test(eventParam)
    ? { eventId: eventParam, teamId: teamParam && uuid.test(teamParam) ? teamParam : undefined } : undefined;

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
      {tab === "calendar" && <BookingCalendar org={org} prefill={prefill} onPrefillUsed={() => router.replace(path)} />}
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
  // A pending series is decided as a whole.
  const series = booking.can_decide && !!booking.series_id;
  const group = booking.can_decide && !booking.series_id && !!booking.group_id;
  const act = async (name: "cancel_booking" | "decide_booking", approve?: boolean) => {
    if (!client) return;
    if (name === "cancel_booking" && !window.confirm("Avboka den här bokningen?")) return;
    const { error: actError } = name === "decide_booking" && series
      ? await client.schema("api").rpc("decide_booking_series", { target_series_id: booking.series_id, approve })
      : name === "decide_booking" && group
      ? await client.schema("api").rpc("decide_booking_group", { target_group_id: booking.group_id, approve })
      : await client.schema("api").rpc(name, name === "cancel_booking"
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
        {booking.series_id && <span>Återkommande · {booking.series_remaining} kommande tillfällen</span>}
        {booking.group_id && (booking.group_resources?.length ?? 0) > 1 && <span>Tillsammans med {booking.group_resources?.filter(name => name !== booking.resource_name).join(", ")}</span>}
        {booking.status === "pending" && <span className="bk-badge">{statusLabels.pending}</span>}
        {error && <span role="alert" className="wt-error">{error}</span>}
      </div>
      <div className="bk-booking-actions">
        {booking.can_decide && <button type="button" className="wt-button small" onClick={() => act("decide_booking", true)}>{series ? "Godkänn serien" : group ? "Godkänn alla" : "Godkänn"}</button>}
        {booking.can_decide && <button type="button" className="wt-button secondary small" onClick={() => act("decide_booking", false)}>{series ? "Neka serien" : group ? "Neka alla" : "Neka"}</button>}
        {booking.can_cancel && !booking.can_decide && <button type="button" className="wt-button secondary small" onClick={() => act("cancel_booking")}>Avboka</button>}
      </div>
    </li>
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
        <ul className="bk-bookings">{bookings.filter((item, index) =>
          (!item.series_id || bookings.findIndex(other => other.series_id === item.series_id) === index)
          && (!item.group_id || bookings.findIndex(other => other.group_id === item.group_id) === index))
          .map(item => <BookingRow key={item.id} booking={item} onChanged={() => { void load(); onChanged(); }} showResource showDate />)}</ul>
      )}
    </section>
  );
}
