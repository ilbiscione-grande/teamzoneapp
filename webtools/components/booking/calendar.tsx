"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  GRID_END, GRID_START, addDays, addMinutes, bookingError, bookingSpan, categoryLabels, categoryOrder, dateKey, dayLabel,
  gridPlacement, groupResources, localInstant, nowFraction, slotAt, statusLabels, weekStart,
  type Booking, type Organization, type Resource, type ResourceCategory,
} from "../../lib/booking";
import { useAccount } from "../account";
import { BookingForm } from "./booking-form";

type View = "day" | "week";
const HOUR_PX = 52;
const hours = Array.from({ length: GRID_END - GRID_START }, (_, index) => GRID_START + index);

/**
 * The booking calendar: a day with the resources side by side, or a week
 * of one resource. Bookings sit on their time; tapping a free time books it.
 */
export function BookingCalendar({ org, prefill, onPrefillUsed }: {
  org: Organization;
  /** From the app's "Boka resurs": open the form for this team and activity. */
  prefill?: { teamId?: string; eventId: string };
  onPrefillUsed?: () => void;
}) {
  const { client } = useAccount();
  const [view, setView] = useState<View>("day");
  const [day, setDay] = useState(() => dateKey(new Date()));
  const [category, setCategory] = useState<ResourceCategory | "all">("all");
  const active = useMemo(() => groupResources(org.resources).flatMap(group => group.items), [org.resources]);
  const [resourceId, setResourceId] = useState<string>(() => active[0]?.id ?? "");
  const [bookings, setBookings] = useState<Booking[] | null>(null);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [draft, setDraft] = useState<{ resource: Resource | null; day: string; start: string; end: string; teamId?: string; eventId?: string } | null>(
    () => prefill ? { resource: null, day: dateKey(new Date()), start: "18:00", end: "19:30", teamId: prefill.teamId, eventId: prefill.eventId } : null);
  const [open, setOpen] = useState<Booking | null>(null);
  const [now, setNow] = useState(() => new Date());
  const scroller = useRef<HTMLDivElement>(null);

  // The minute line moves with the clock.
  useEffect(() => { const timer = setInterval(() => setNow(new Date()), 60_000); return () => clearInterval(timer); }, []);

  const days = view === "day" ? [day] : Array.from({ length: 7 }, (_, index) => addDays(weekStart(day), index));
  const range = { from: localInstant(days[0], "00:00"), to: localInstant(addDays(days[days.length - 1], 1), "00:00") };

  const load = useCallback(async () => {
    if (!client) return;
    setBookings(null);
    const { data, error: loadError } = await client.schema("api").rpc("list_bookings", { target_organization_id: org.id, range_start: range.from, range_end: range.to });
    if (loadError) { setError(bookingError(loadError)); setBookings([]); return; }
    setError("");
    setBookings(data as Booking[]);
  }, [client, org.id, range.from, range.to]);

  useEffect(() => { void load(); }, [load]);

  // Open at the working day rather than at six in the morning.
  useEffect(() => {
    const target = Math.max((Math.min(new Date().getHours(), 17) - 1 - GRID_START), 1) * HOUR_PX;
    scroller.current?.scrollTo({ top: target });
  }, [view]);

  const categories = categoryOrder.filter(value => active.some(resource => resource.category === value));
  const shown = category === "all" ? active : active.filter(resource => resource.category === category);
  const weekResource = active.find(resource => resource.id === resourceId) ?? active[0];
  const columns: { key: string; resource: Resource; day: string; title: string; subtitle: string }[] = view === "day"
    ? shown.map(resource => ({ key: resource.id, resource, day, title: resource.name, subtitle: categoryLabels[resource.category] }))
    : weekResource ? days.map(item => {
      const [y, m, d] = item.split("-").map(Number);
      const date = new Date(y, m - 1, d);
      return { key: item, resource: weekResource, day: item, title: date.toLocaleDateString("sv-SE", { weekday: "short" }), subtitle: date.toLocaleDateString("sv-SE", { day: "numeric", month: "short" }) };
    }) : [];

  const step = (direction: number) => setDay(addDays(day, direction * (view === "day" ? 1 : 7)));
  const title = view === "day"
    ? dayLabel(day)
    : `Vecka ${isoWeek(days[0])} · ${new Date(range.from).toLocaleDateString("sv-SE", { day: "numeric", month: "short" })} – ${new Date(localInstant(days[6], "12:00")).toLocaleDateString("sv-SE", { day: "numeric", month: "short" })}`;

  const tap = (event: React.MouseEvent<HTMLDivElement>, resource: Resource, columnDay: string) => {
    const box = event.currentTarget.getBoundingClientRect();
    const start = slotAt((event.clientY - box.top) / box.height);
    if (new Date(localInstant(columnDay, addMinutes(start, 30))) <= new Date()) {
      setNotice("Den tiden har redan passerat.");
      return;
    }
    setNotice("");
    setDraft({ resource, day: columnDay, start, end: addMinutes(start, 60) });
  };

  if (active.length === 0) {
    return (
      <div className="wt-panel">
        <p>Det finns inga resurser att boka än.</p>
        {org.role === "admin" && <p className="wt-small">Lägg upp planer, lokaler, fordon eller utrustning under Resurser.</p>}
      </div>
    );
  }

  return (
    <section className="cal" aria-label="Kalender">
      <div className="cal-toolbar">
        <div className="cal-nav">
          <button type="button" className="wt-button secondary small" onClick={() => step(-1)} aria-label={view === "day" ? "Föregående dag" : "Föregående vecka"}>‹</button>
          <button type="button" className="wt-button secondary small" onClick={() => setDay(dateKey(new Date()))}>Idag</button>
          <button type="button" className="wt-button secondary small" onClick={() => step(1)} aria-label={view === "day" ? "Nästa dag" : "Nästa vecka"}>›</button>
          <label className="cal-title">
            <span>{title}</span>
            <input type="date" value={day} onChange={event => event.target.value && setDay(event.target.value)} aria-label="Välj datum" />
          </label>
        </div>
        <div className="cal-views" role="tablist" aria-label="Vy">
          <button type="button" role="tab" aria-selected={view === "day"} onClick={() => setView("day")}>Dag</button>
          <button type="button" role="tab" aria-selected={view === "week"} onClick={() => setView("week")}>Vecka</button>
        </div>
      </div>
      <div className="cal-filters">
        {view === "day" ? (
          categories.length > 1 && (
            <div className="cal-chips" role="group" aria-label="Visa resurser">
              <button type="button" aria-pressed={category === "all"} onClick={() => setCategory("all")}>Alla</button>
              {categories.map(value => <button key={value} type="button" aria-pressed={category === value} onClick={() => setCategory(value)}>{categoryLabels[value]}</button>)}
            </div>
          )
        ) : (
          <label className="cal-resource">Resurs
            <select value={weekResource?.id} onChange={event => setResourceId(event.target.value)}>
              {groupResources(org.resources).map(group => (
                <optgroup key={group.category} label={categoryLabels[group.category]}>
                  {group.items.map(resource => <option key={resource.id} value={resource.id}>{resource.name}</option>)}
                </optgroup>
              ))}
            </select>
          </label>
        )}
        <span className="wt-small cal-hint">Tryck på en ledig tid för att boka.</span>
      </div>
      {notice && <p className="wt-note" role="status">{notice}</p>}
      {error && <p className="wt-error" role="alert">{error}</p>}

      <div className="cal-frame" ref={scroller} aria-busy={bookings === null}>
        <div className="cal-grid" style={{ gridTemplateColumns: `56px repeat(${columns.length}, minmax(${view === "day" ? 150 : 110}px, 1fr))` }}>
          <div className="cal-corner" />
          {columns.map(column => (
            <div key={column.key} className="cal-head" data-today={column.day === dateKey(now) && view === "week"}>
              <strong>{column.title}</strong>
              <span>{column.subtitle}{column.resource.requires_approval && view === "day" ? " · godkänns" : ""}</span>
            </div>
          ))}
          <div className="cal-hours" style={{ height: hours.length * HOUR_PX }}>
            {hours.map(hour => <span key={hour} style={{ top: (hour - GRID_START) * HOUR_PX }}>{String(hour).padStart(2, "0")}:00</span>)}
          </div>
          {columns.map(column => {
            const line = nowFraction(column.day, now);
            const own = (bookings ?? []).filter(booking => booking.resource_id === column.resource.id);
            return (
              <div
                key={column.key}
                className="cal-column"
                style={{ height: hours.length * HOUR_PX }}
                data-past={new Date(localInstant(addDays(column.day, 1), "00:00")) <= now}
                onClick={event => { if (event.target === event.currentTarget) tap(event, column.resource, column.day); }}
                role="presentation"
              >
                {line !== null && <div className="cal-now" style={{ top: `${line * 100}%` }} aria-hidden="true" />}
                {own.map(booking => {
                  const place = gridPlacement(booking.starts_at, booking.ends_at, column.day);
                  if (!place) return null;
                  return (
                    <button
                      key={booking.id}
                      type="button"
                      className="cal-booking"
                      data-status={booking.status}
                      data-mine={booking.is_mine}
                      data-cut-top={place.cutTop}
                      data-cut-bottom={place.cutBottom}
                      style={{ top: `${place.top * 100}%`, height: `${place.height * 100}%` }}
                      onClick={() => setOpen(booking)}
                      aria-label={`${bookingSpan(booking.starts_at, booking.ends_at)} ${booking.title ?? "Bokad"}${booking.status === "pending" ? ", väntar på godkännande" : ""}`}
                    >
                      <span className="cal-booking-time">{bookingSpan(booking.starts_at, booking.ends_at)}</span>
                      <strong>{booking.title ?? booking.team_name ?? "Bokad"}</strong>
                      <span>{[booking.title ? booking.team_name : null, booking.is_mine ? "Du" : booking.booked_by_name].filter(Boolean).join(" · ")}</span>
                    </button>
                  );
                })}
              </div>
            );
          })}
        </div>
      </div>
      <div className="cal-legend" aria-hidden="true">
        <span data-status="confirmed">Bokad</span>
        <span data-status="pending">Väntar på godkännande</span>
        <span data-mine="true">Din bokning</span>
      </div>

      {draft && (
        <BookingForm org={org} resource={draft.resource} day={draft.day} startTime={draft.start} endTime={draft.end}
          teamId={draft.teamId} eventId={draft.eventId}
          onClose={() => { if (draft.eventId) onPrefillUsed?.(); setDraft(null); }}
          onBooked={status => {
            if (draft.eventId) onPrefillUsed?.();
            setDraft(null);
            setNotice(status === "pending" ? "Förfrågan är skickad. Den visas som väntande tills en administratör har godkänt den." : "Bokningen är klar.");
            void load();
          }} />
      )}
      {open && <BookingDetails booking={open} onClose={() => setOpen(null)} onChanged={() => { setOpen(null); void load(); }} />}
    </section>
  );
}

/** ISO week number of a local date key. */
function isoWeek(key: string): number {
  const [y, m, d] = key.split("-").map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  const weekday = (date.getUTCDay() + 6) % 7;
  date.setUTCDate(date.getUTCDate() - weekday + 3);
  const firstThursday = new Date(Date.UTC(date.getUTCFullYear(), 0, 4));
  return 1 + Math.round((date.getTime() - firstThursday.getTime()) / (7 * 86400e3) - ((firstThursday.getUTCDay() + 6) % 7 - 3) / 7);
}

/** A booking's details with cancel, approve and decline. */
function BookingDetails({ booking, onClose, onChanged }: { booking: Booking; onClose: () => void; onChanged: () => void }) {
  const { client } = useAccount();
  const dialog = useRef<HTMLDialogElement>(null);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  useEffect(() => { dialog.current?.showModal(); }, []);
  const act = async (name: "cancel_booking" | "decide_booking", approve?: boolean) => {
    if (!client) return;
    if (name === "cancel_booking" && !window.confirm("Avboka den här bokningen?")) return;
    setBusy(true);
    const { error: actError } = await client.schema("api").rpc(name, name === "cancel_booking" ? { target_booking_id: booking.id } : { target_booking_id: booking.id, approve });
    setBusy(false);
    if (actError) { setError(bookingError(actError)); return; }
    onChanged();
  };
  const start = new Date(booking.starts_at);
  return (
    <dialog ref={dialog} className="bk-dialog" onClose={onClose} aria-labelledby="booking-details-title">
      <h2 id="booking-details-title">{booking.title ?? booking.resource_name}</h2>
      <dl className="wt-facts">
        <dt>Resurs</dt><dd>{booking.resource_name}</dd>
        <dt>Tid</dt><dd>{start.toLocaleDateString("sv-SE", { weekday: "long", day: "numeric", month: "long" })} · {bookingSpan(booking.starts_at, booking.ends_at)}</dd>
        <dt>Status</dt><dd>{statusLabels[booking.status]}</dd>
        <dt>Bokad av</dt><dd>{booking.is_mine ? "Du" : booking.booked_by_name ?? "Okänd"}</dd>
        {booking.team_name && <><dt>Lag</dt><dd>{booking.team_name}</dd></>}
        {booking.event_title && <><dt>Aktivitet</dt><dd>{booking.event_title}</dd></>}
        {booking.notes && <><dt>Anteckning</dt><dd>{booking.notes}</dd></>}
      </dl>
      {error && <p role="alert" className="wt-error">{error}</p>}
      <div className="wt-actions">
        {booking.can_decide && <button type="button" className="wt-button" disabled={busy} onClick={() => act("decide_booking", true)}>Godkänn</button>}
        {booking.can_decide && <button type="button" className="wt-button secondary" disabled={busy} onClick={() => act("decide_booking", false)}>Neka</button>}
        {booking.can_cancel && <button type="button" className="wt-button secondary" disabled={busy} onClick={() => act("cancel_booking")}>Avboka</button>}
        <button type="button" className="wt-button secondary" onClick={() => dialog.current?.close()}>Stäng</button>
      </div>
    </dialog>
  );
}
