"use client";

import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useCallback, useEffect, useRef, useState } from "react";
import { addDays, bookingError, bookingSpan, dateKey, dayLabel, kindLabels, statusLabels, type Booking, type Organization } from "../../lib/booking";
import { myBookingEntries, type MyBookingStatus } from "../../lib/my-bookings";
import { bookingRequests, filterBookingRequests, requestKindLabels, type BookingRequest, type RequestKind } from "../../lib/booking-requests";
import { RequestReview } from "./request-review";
import { bookingCommand, bookingRevisions } from "../../lib/booking-command";
import { useAccount } from "../account";
import { BookingSeriesPlans } from "./series-plans";
import { BookingCalendar, BookingDetails } from "./calendar";
import { ResourceOverview } from "./resource-overview";
import { ResourcesAdmin, SettingsAdmin } from "./admin";
import { BookingForm } from "./booking-form";
import { WorkspaceOverview } from "./workspace-overview";
import { BookingCard } from "./booking-card";
import "./workspace.css";

type Tab = "overview" | "availability" | "series" | "calendar" | "mine" | "pending" | "resources" | "settings";

export function BookingOrganization({ id }: { id: string }) {
  const { client } = useAccount();
  const [org, setOrg] = useState<Organization | null>(null);
  const [error, setError] = useState("");
  const [tab, setTab] = useState<Tab>("overview");
  const [seriesTarget,setSeriesTarget] = useState<string|null>(null);
  const [creating, setCreating] = useState(false);
  const [notice, setNotice] = useState("");
  const [refresh, setRefresh] = useState(0);
  const [detailsBooking, setDetailsBooking] = useState<Booking | null>(null);
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
  const current = prefill ? "calendar" : tab;
  const changed = (message?: string) => { if (message) setNotice(message); setRefresh(value => value + 1); void load(); };
  const navigate = (value: Tab) => { setDetailsBooking(null); setSeriesTarget(null); setTab(value); if (prefill) router.replace(path); };
  const tabs: [Tab, string][] = [
    ["overview", "Översikt"],
    ["calendar", "Kalender"],
    ["availability", "Tillgänglighet"],
    ["mine", "Mina bokningar"],
    ["series", "Återkommande bokningar"],
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
        <div className="bk-org-actions"><Link className="wt-link" href="/bokningar">Byt organisation</Link>
          <button className="wt-button" type="button" disabled={!org.resources.some(resource => resource.active)} onClick={() => { setNotice(""); setCreating(true); }}>+ Ny bokning</button>
        </div>
      </div>
      {notice && <p className="wt-note" role="status">{notice}</p>}
      <div className="bk-workspace-layout">
      <label className="bk-mobile-nav">Visa vy
        <select value={current} onChange={event => navigate(event.target.value as Tab)}>
          {tabs.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
        </select>
      </label>
      <nav className="bk-workspace-nav" aria-label="Bokningshanterare">
        {tabs.map(([value, label]) => (
          <div key={value}>{value === "pending" && <p className="bk-nav-section">Administration</p>}<button type="button" aria-current={current === value ? "page" : undefined} onClick={() => navigate(value)}>{label}</button></div>
        ))}
      </nav>
      <div className="bk-workspace-content" key={current === "mine" ? "mine" : refresh}>
      {current === "overview" && <WorkspaceOverview org={org} onCalendar={() => navigate("calendar")} onAvailability={() => navigate("availability")} onOpen={setDetailsBooking} onSeries={bookingId=>{navigate('series');setSeriesTarget(bookingId);}} pending={admin ? <Pending org={org} onChanged={changed} limit={3} onShowAll={() => navigate("pending")} /> : undefined} />}
      {current === "calendar" && <BookingCalendar org={org} prefill={prefill} onPrefillUsed={() => { setTab("calendar"); router.replace(path); }} />}
      {current === "availability" && <ResourceOverview org={org} />}
      {current === "series" && <BookingSeriesPlans key={seriesTarget??'all'} organizationId={org.id} resources={org.resources} initialBookingId={seriesTarget??undefined} />}
      {current === "mine" && <MyBookings org={org} refreshKey={refresh} onOpen={setDetailsBooking} />}
      {current === "pending" && admin && <Pending org={org} onChanged={message => { if (message) setNotice(message); void load(); }} />}
      {current === "resources" && admin && <ResourcesAdmin org={org} onChanged={load} />}
      {current === "settings" && admin && <SettingsAdmin org={org} onChanged={load} />}
      </div></div>
      {detailsBooking && <BookingDetails org={org} resources={org.resources} booking={detailsBooking} onClose={() => setDetailsBooking(null)} onChanged={() => { setDetailsBooking(null); changed(); }} />}
      {creating && <BookingForm org={org} resource={null} day={new Date().getHours() >= 18 ? addDays(dateKey(new Date()), 1) : dateKey(new Date())} onClose={() => setCreating(false)} onBooked={(status, count, kind) => {
        setCreating(false);
        setNotice(`${status === "pending" ? "Förfrågan skickad för godkännande" : "Bokningen är bekräftad"}${count ? ` · ${count} ${kind === "resources" ? "resurser" : "tillfällen"}` : ""}.`);
        changed();
      }} />}
    </div>
  );
}

function BookingRow({ booking, onChanged, showResource = false, showDate = false, request, onOpen, resourceLabel, resourceCount }: { resourceLabel?: string; resourceCount?: number; booking: Booking; onChanged: (message?: string) => void; showResource?: boolean; showDate?: boolean; request?: BookingRequest; onOpen?: (booking: Booking) => void }) {
  const { client } = useAccount();
  const [error, setError] = useState("");
  const [reviewing, setReviewing] = useState(false);
  const [busy, setBusy] = useState(false);
  // A pending series is decided as a whole.
  const series = booking.can_decide && !!booking.series_id;
  const group = booking.can_decide && !booking.series_id && !!booking.group_id;
  const act = async (name: "cancel_booking" | "decide_booking", approve?: boolean) => {
    if (!client || busy) return;
    if (name === "cancel_booking" && !window.confirm("Avboka den här bokningen?")) return;
    setBusy(true);
    setError("");
    try {
    const { error: actError } = name === "decide_booking" && series
      ? await bookingCommand(client, "decide_booking_series", { target_series_id: booking.series_id, approve }, bookingRevisions(booking, "decide_booking_series"))
      : name === "decide_booking" && group
      ? await bookingCommand(client, "decide_booking_group", { target_group_id: booking.group_id, approve }, bookingRevisions(booking, "decide_booking_group"))
      : await bookingCommand(client, name, name === "cancel_booking"
        ? { target_booking_id: booking.id } : { target_booking_id: booking.id, approve }, bookingRevisions(booking, name));
    if (actError) { setError(bookingError(actError)); return; }
    onChanged(name === "decide_booking" ? approve ? "Förfrågan har godkänts." : "Förfrågan har nekats." : undefined);
    } catch { setError("Det gick inte att spara beslutet. Försök igen."); }
    finally { setBusy(false); }
  };
  return (
    <li className="bk-booking" data-status={booking.status}>
      <div className="bk-booking-time">
        {showDate && <span>{new Date(booking.starts_at).toLocaleDateString("sv-SE", { weekday: "short", day: "numeric", month: "short" })}</span>}
        <strong>{bookingSpan(booking.starts_at, booking.ends_at)}</strong>
      </div>
      <div className="bk-booking-body">
        <strong>{[showResource ? (resourceLabel ?? booking.resource_name) : null, booking.title].filter(Boolean).join(" · ") || "Bokad"}</strong>
        <span>{[booking.team_name, booking.event_title ? `till ${booking.event_title}` : null, booking.is_mine ? "Du" : booking.booked_by_name].filter(Boolean).join(" · ")}</span>
        {request ? <span>{requestKindLabels[request.kind]} · {request.pending.length} {request.pending.length === 1 ? "väntande resursbokning" : "väntande resursbokningar"}</span> : booking.series_id && <span>Återkommande · {booking.series_remaining} kommande tillfällen</span>}
        {!resourceLabel && booking.group_id && (booking.group_resources?.length ?? 0) > 1 && <span>Tillsammans med {booking.group_resources?.filter(name => name !== booking.resource_name).join(", ")}</span>}
        {(onOpen || booking.status === "pending") && <span className="bk-badge">{statusLabels[booking.status]}{resourceCount && resourceCount > 1 ? ` · ${resourceCount} resurser` : ""}</span>}
        {error && <span role="alert" className="wt-error">{error}</span>}
      </div>
      <div className="bk-booking-actions">
        {onOpen ? <button type="button" className="wt-button secondary small" aria-label={`Öppna bokning för ${resourceLabel ?? booking.resource_name}`} onClick={() => onOpen(booking)}>Öppna bokning</button> : <>
        {booking.can_decide && <button type="button" className="wt-button secondary small" aria-expanded={reviewing} onClick={() => setReviewing(!reviewing)}>{reviewing ? "Stäng granskning" : "Granska förfrågan"}</button>}
        {booking.can_cancel && !booking.can_decide && <button type="button" disabled={busy} className="wt-button secondary small" onClick={() => act("cancel_booking")}>{busy ? "Avbokar…" : "Avboka"}</button>}
        </>}
      </div>
      {booking.can_decide && reviewing && <div className="bk-review">
        {request ? <RequestReview request={request} /> : <>
        <p><strong>{series ? "Beslutet gäller alla väntande tillfällen i serien." : group ? "Beslutet gäller alla väntande resurser i gruppen." : "Beslutet gäller den här bokningen."}</strong></p>
        {booking.group_resources && booking.group_resources.length > 1 && <p>Resurser: {booking.group_resources.join(", ")}</p>}
        {booking.notes && <p>Anteckning: {booking.notes}</p>}
        <p className="wt-small">Uppgifterna kontrolleras igen när beslutet sparas. Redan bekräftade bokningar lämnas kvar.</p></>}
        <div className="bk-booking-actions" aria-busy={busy}>
          <button type="button" disabled={busy} className="wt-button secondary small" onClick={() => act("decide_booking", false)}>{series ? "Neka väntande i serien" : group ? "Neka väntande i gruppen" : "Neka"}</button>
          <button type="button" disabled={busy} className="wt-button small" onClick={() => act("decide_booking", true)}>{busy ? "Sparar…" : series ? "Godkänn väntande i serien" : group ? "Godkänn väntande i gruppen" : "Godkänn"}</button>
        </div>
      </div>}
    </li>
  );
}

/** Your coming bookings in the next two months. */
function MyBookings({ org, onOpen, refreshKey }: { org: Organization; onOpen: (booking: Booking) => void; refreshKey: number }) {
  const { client } = useAccount();
  const [bookings, setBookings] = useState<Booking[] | null>(null);
  const [error, setError] = useState("");
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState<MyBookingStatus>("all");
  const [days, setDays] = useState(60);
  const [filtersOpen, setFiltersOpen] = useState(false);
  const [loadedAt, setLoadedAt] = useState(() => Date.now());
  const [refreshing, setRefreshing] = useState(false);
  const generation = useRef(0);
  const load = useCallback(async () => {
    if (!client) return;
    const request = ++generation.current;
    setRefreshing(true);
    setError("");
    const from = new Date();
    const to = new Date(from.getTime() + 60 * 86400e3);
    try {
    const { data, error: loadError } = await client.schema("api").rpc("list_bookings", { target_organization_id: org.id, range_start: from.toISOString(), range_end: to.toISOString() });
    if (request !== generation.current) return;
    if (loadError) { setError(bookingError(loadError)); return; }
    setLoadedAt(from.getTime());
    setBookings(((data ?? []) as Booking[]).filter(item => item.is_mine));
    } catch {
      if (request === generation.current) setError("Bokningarna kunde inte hämtas. Försök igen.");
    } finally {
      if (request === generation.current) setRefreshing(false);
    }
  }, [client, org.id]);
  useEffect(() => { void load(); return () => { generation.current++; }; }, [load, refreshKey]);
  if (error) return <div className="wt-panel"><p className="wt-error" role="alert">{error}</p><button type="button" className="wt-button secondary" onClick={() => void load()}>Försök igen</button></div>;
  if (!bookings) return <p className="wt-status">Laddar…</p>;
  const all = myBookingEntries(bookings,org.resources,"","all",60,loadedAt).flatMap(group => group.entries);
  const groups = myBookingEntries(bookings,org.resources,query,status,days,loadedAt);
  const filtered = !!query.trim() || status !== "all" || days !== 60;
  const filterCount = Number(status !== "all") + Number(days !== 60);
  return (
    <section className="wt-panel" aria-label="Mina bokningar" aria-busy={refreshing}>
      <div className="bk-panel-heading bk-my-heading"><h2>Mina bokningar</h2><button type="button" className="wt-button secondary small bk-my-refresh" aria-label={refreshing ? "Uppdaterar bokningar" : "Uppdatera bokningar"} title="Uppdatera bokningar" aria-disabled={refreshing} onClick={() => { if (!refreshing) void load(); }}><span aria-hidden="true">↻</span><span className="bk-my-refresh-text">{refreshing ? "Uppdaterar…" : "Uppdatera"}</span></button></div>
      <p className="wt-small">Dina pågående och kommande bokningar, upp till 60 dagar framåt.</p>
      <div className="bk-my-bookings-totals" role="group" aria-label="Filtrera mina bokningar efter status">
        <button type="button" aria-pressed={status === "confirmed"} onClick={() => setStatus(value => value === "confirmed" ? "all" : "confirmed")}>Bokade <strong>{all.filter(entry => entry.booking.status === "confirmed").length}</strong></button>
        <button type="button" aria-label={`Väntar på godkännande: ${all.filter(entry => entry.booking.status === "pending").length}`} aria-pressed={status === "pending"} onClick={() => setStatus(value => value === "pending" ? "all" : "pending")}>Väntande <strong>{all.filter(entry => entry.booking.status === "pending").length}</strong></button>
      </div>
      <div className="bk-resource-controls bk-request-controls bk-my-controls">
        <label>Sök bland mina bokningar<input type="search" value={query} onChange={event => setQuery(event.target.value)} placeholder="Resurs, lag eller rubrik" /></label>
        <button type="button" className="wt-button secondary small bk-my-filter-toggle" aria-expanded={filtersOpen} aria-controls={`my-booking-filters-${org.id}`} onClick={() => setFiltersOpen(value => !value)}>Filter{filterCount > 0 ? ` · ${filterCount}` : ""}</button>
        <div id={`my-booking-filters-${org.id}`} className="bk-my-booking-filters" data-expanded={filtersOpen}>
        <label>Bokningsstatus<select value={status} onChange={event => setStatus(event.target.value as MyBookingStatus)}><option value="all">Alla kommande</option><option value="confirmed">Bokade</option><option value="pending">Väntar på godkännande</option></select></label>
        <label>Period<select value={days} onChange={event => setDays(Number(event.target.value))}><option value={7}>Närmaste 7 dagarna</option><option value={30}>Närmaste 30 dagarna</option><option value={60}>Närmaste 60 dagarna</option></select></label>
        </div>
      </div>
      <div className="bk-panel-heading"><p className="wt-small" role="status">{refreshing ? "Uppdaterar bokningar. Ditt urval ligger kvar." : `Visar ${groups.reduce((count,group) => count + group.entries.length,0)} av ${all.length} bokningar · närmast i tid först${status !== "all" ? ` · ${statusLabels[status]}` : ""}${days !== 60 ? ` · ${days} dagar` : ""}`}</p>{filtered && <button type="button" className="wt-link-button" onClick={() => { setQuery(""); setStatus("all"); setDays(60); }}>Rensa bokningsurval</button>}</div>
      {bookings.length === 0 ? <p>Du har inga kommande bokningar de närmaste två månaderna.</p> : (
        groups.length === 0 ? <p className="wt-note">Inga bokningar matchar urvalet. Rensa sökningen eller välj en annan status eller period.</p> : groups.map(group => <section key={group.day} className="bk-my-booking-day" aria-label={dayLabel(group.day)}><h3>{dayLabel(group.day)}</h3><ul className="bk-bookings">{group.entries.map(item => <BookingCard key={item.key} booking={item.booking} resourceLabel={item.resourceLabel} resourceCount={item.items.length} onOpen={onOpen} showOwner />)}</ul></section>)
      )}
    </section>
  );
}

function Pending({ org, onChanged, limit, onShowAll }: { org: Organization; onChanged: (message?: string) => void; limit?: number; onShowAll?: () => void }) {
  const { client } = useAccount();
  const [bookings, setBookings] = useState<Booking[] | null>(null);
  const [error, setError] = useState("");
  const [query, setQuery] = useState("");
  const [kind, setKind] = useState<RequestKind | "all">("all");
  const [filtersOpen, setFiltersOpen] = useState(false);
  const load = useCallback(async () => {
    if (!client) return;
    setError("");
    const { data, error: loadError } = await client.schema("api").rpc("list_pending_bookings", { target_organization_id: org.id });
    if (loadError) { setError(bookingError(loadError)); return; }
    setBookings(data as Booking[]);
  }, [client, org.id]);
  useEffect(() => { void load(); }, [load]);
  if (error) return <div className="wt-panel"><p className="wt-error" role="alert">{error}</p><button type="button" className="wt-button secondary" onClick={() => void load()}>Försök igen</button></div>;
  if (!bookings) return <p className="wt-status">Laddar…</p>;
  const decisions = bookingRequests(bookings);
  const shown = limit ? decisions : filterBookingRequests(decisions, query, kind);
  if (limit && decisions.length === 0) return (
    <section className="wt-panel bk-overview-clear" aria-label="Att godkänna">
      <p>Inga väntande förfrågningar.</p>
      <button type="button" className="wt-link-button" onClick={onShowAll}>Visa förfrågningar</button>
    </section>
  );
  return (
    <section className="wt-panel" aria-label="Att godkänna">
      <div className="bk-panel-heading"><h3>Att hantera{decisions.length ? ` · ${decisions.length}` : ""}</h3>{limit && decisions.length > limit && <button type="button" className="wt-button secondary small" onClick={onShowAll}>Visa alla förfrågningar</button>}</div>
      {!limit && <>
        <p className="wt-small">Granska förfrågningar. Grupper och serier hanteras tillsammans.</p>
        <div className="bk-request-summary" aria-label="Väntande förfrågningar"><strong>{decisions.length}</strong> förfrågningar · <strong>{decisions.reduce((count,item) => count + item.pending.length,0)}</strong> resursbokningar · <strong>{decisions.filter(item => item.kind === "series").length}</strong> serier</div>
        <div className="bk-resource-controls bk-request-controls bk-pending-controls">
          <label>Sök förfrågan<input type="search" value={query} onChange={event => setQuery(event.target.value)} placeholder="Resurs, lag, rubrik eller bokare" /></label>
          <button type="button" className="wt-button secondary small bk-pending-filter-toggle" aria-expanded={filtersOpen} aria-controls={`pending-filters-${org.id}`} onClick={() => setFiltersOpen(value => !value)}>Filter{kind !== "all" ? " · 1" : ""}</button>
          <div id={`pending-filters-${org.id}`} className="bk-pending-filters" data-expanded={filtersOpen}>
          <label>Typ av förfrågan<select value={kind} onChange={event => setKind(event.target.value as RequestKind | "all")}><option value="all">Alla typer</option>{Object.entries(requestKindLabels).map(([value,label]) => <option key={value} value={value}>{label}</option>)}</select></label>
          </div>
        </div>
        <div className="bk-panel-heading"><p className="wt-small" role="status">Visar {shown.length} av {decisions.length} förfrågningar · närmast i tid först{kind !== "all" ? ` · ${requestKindLabels[kind]}` : ""}</p>{(query.trim() || kind !== "all") && <button type="button" className="wt-link-button" onClick={() => { setQuery(""); setKind("all"); }}>Rensa sökning och typ</button>}</div>
      </>}
      {bookings.length === 0 ? <p>Inga förfrågningar väntar på godkännande.</p> : (
        shown.length === 0 ? <p className="wt-note">Inga förfrågningar matchar urvalet. Rensa sökningen eller välj en annan typ.</p> : <ul className="bk-bookings">{shown.slice(0, limit)
          .map(item => <BookingRow key={item.key} booking={item.booking} request={item} onChanged={message => { void load(); onChanged(message); }} showResource showDate />)}</ul>
      )}
    </section>
  );
}
