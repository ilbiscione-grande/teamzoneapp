"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  activeFilterCount, addDays, addMinutes, bookingError, bookingSpan, categoryLabels, dateKey, dayLabel, emptyFilter,
  gridPlacement, groupResources, localInstant, matchesFilter, nowFraction, parseFilter, slotAt, statusLabels, weekStart,
  type Booking, type CalendarFilter, type Organization, type Resource,
} from "../../lib/booking";
import { useAccount } from "../account";
import { BookingForm } from "./booking-form";

type View = "day" | "week";
const HOUR_PX = 52;

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
  const active = useMemo(() => groupResources(org.resources).flatMap(group => group.items), [org.resources]);
  // What the calendar shows, kept per organisation in this browser.
  const storageKey = `wt-booking-filter-${org.id}`;
  const [filter, setFilterState] = useState<CalendarFilter>(emptyFilter);
  const [filtering, setFiltering] = useState(false);
  useEffect(() => {
    try { setFilterState(parseFilter(window.localStorage.getItem(storageKey)) ?? emptyFilter); } catch { /* storage off */ }
  }, [storageKey]);
  const setFilter = (next: CalendarFilter) => {
    setFilterState(next);
    try { window.localStorage.setItem(storageKey, JSON.stringify(next)); } catch { /* storage off */ }
  };
  const hours = Array.from({ length: filter.range.end - filter.range.start }, (_, index) => filter.range.start + index);
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
    const target = Math.max((Math.min(new Date().getHours(), 17) - 1 - filter.range.start), 0) * HOUR_PX;
    scroller.current?.scrollTo({ top: target });
  }, [view, filter.range.start]);

  const shown = filter.resourceIds === null ? active : active.filter(resource => filter.resourceIds!.includes(resource.id));
  // Teams to filter by: yours, and those with bookings in view.
  const teams = new Map<string, string>(org.teams.map(team => [team.team_id, team.name]));
  for (const booking of bookings ?? []) if (booking.team_id && booking.team_name) teams.set(booking.team_id, booking.team_name);
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
    const start = slotAt((event.clientY - box.top) / box.height, filter.range);
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
        <button type="button" className="wt-button secondary small cal-filter-button" aria-expanded={filtering} onClick={() => setFiltering(!filtering)}>
          Filter{activeFilterCount(filter) > 0 ? ` (${activeFilterCount(filter)})` : ""}
        </button>
        {view === "week" && (
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
      {filtering && (
        <FilterPanel org={org} filter={filter} teams={[...teams.entries()].sort((a, b) => a[1].localeCompare(b[1], "sv"))} onChange={setFilter} />
      )}
      {view === "day" && shown.length === 0 && <p className="wt-note">Inga resurser matchar filtret. Välj resurser under Filter.</p>}
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
            {hours.map(hour => <span key={hour} style={{ top: (hour - filter.range.start) * HOUR_PX }}>{String(hour).padStart(2, "0")}:00</span>)}
          </div>
          {columns.map(column => {
            const line = nowFraction(column.day, now, filter.range);
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
                  const place = gridPlacement(booking.starts_at, booking.ends_at, column.day, filter.range);
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
                      data-dimmed={!matchesFilter(booking, filter)}
                      style={{ top: `${place.top * 100}%`, height: `${place.height * 100}%` }}
                      onClick={() => setOpen(booking)}
                      aria-label={`${bookingSpan(booking.starts_at, booking.ends_at)} ${booking.title ?? "Bokad"}${booking.status === "pending" ? ", väntar på godkännande" : ""}`}
                    >
                      <span className="cal-booking-time">{bookingSpan(booking.starts_at, booking.ends_at)}{booking.series_id ? " ↻" : ""}</span>
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
          onBooked={(status, count, kind) => {
            if (draft.eventId) onPrefillUsed?.();
            setDraft(null);
            const what = count ? `${count} ${kind === "resources" ? "resurser" : "tillfällen"}` : "Bokningen";
            setNotice(status === "pending"
              ? `Förfrågan för ${count ? what.toLowerCase() : "bokningen"} är skickad. Den visas som väntande tills en administratör har godkänt den.`
              : count ? `${what} är bokade.` : "Bokningen är klar.");
            void load();
          }} />
      )}
      {open && <BookingDetails booking={open} onClose={() => setOpen(null)} onChanged={() => { setOpen(null); void load(); }} />}
    </section>
  );
}

/** Which resources, teams' bookings, hours and bookings the calendar shows. */
function FilterPanel({ org, filter, teams, onChange }: {
  org: Organization;
  filter: CalendarFilter;
  teams: [string, string][];
  onChange: (next: CalendarFilter) => void;
}) {
  const groups = groupResources(org.resources);
  const allIds = groups.flatMap(group => group.items.map(item => item.id));
  const shownIds = filter.resourceIds ?? allIds;
  const setResources = (ids: string[]) => onChange({ ...filter, resourceIds: ids.length === allIds.length ? null : ids });
  const teamKeys = [...teams.map(([id]) => id), "none"];
  const shownTeams = filter.teams ?? teamKeys;
  const setTeams = (ids: string[]) => onChange({ ...filter, teams: ids.length === teamKeys.length ? null : ids });
  const hourOptions = Array.from({ length: 25 }, (_, hour) => hour);
  return (
    <div className="wt-panel cal-filter-panel">
      <fieldset>
        <legend>Resurser</legend>
        <div className="cal-filter-actions">
          <button type="button" className="wt-link-button" onClick={() => setResources(allIds)}>Alla</button>
          <button type="button" className="wt-link-button" onClick={() => setResources([])}>Inga</button>
        </div>
        {groups.map(group => {
          const ids = group.items.map(item => item.id);
          const all = ids.every(id => shownIds.includes(id));
          return (
            <div key={group.category} className="cal-filter-group">
              <label className="wt-check cal-filter-category">
                <input type="checkbox" checked={all} onChange={() => setResources(all ? shownIds.filter(id => !ids.includes(id)) : [...new Set([...shownIds, ...ids])])} />
                <span>{categoryLabels[group.category]}</span>
              </label>
              {group.items.map(item => (
                <label key={item.id} className="wt-check">
                  <input type="checkbox" checked={shownIds.includes(item.id)} onChange={() => setResources(shownIds.includes(item.id) ? shownIds.filter(id => id !== item.id) : [...shownIds, item.id])} />
                  <span>{item.name}</span>
                </label>
              ))}
            </div>
          );
        })}
      </fieldset>
      <fieldset>
        <legend>Lagens bokningar</legend>
        <p className="wt-small">Andra bokningar tonas ner, så att du ser att tiden är upptagen.</p>
        {teams.map(([id, name]) => (
          <label key={id} className="wt-check">
            <input type="checkbox" checked={shownTeams.includes(id)} onChange={() => setTeams(shownTeams.includes(id) ? shownTeams.filter(key => key !== id) : [...shownTeams, id])} />
            <span>{name}</span>
          </label>
        ))}
        <label className="wt-check">
          <input type="checkbox" checked={shownTeams.includes("none")} onChange={() => setTeams(shownTeams.includes("none") ? shownTeams.filter(key => key !== "none") : [...shownTeams, "none"])} />
          <span>Utan lag</span>
        </label>
        <label className="wt-check"><input type="checkbox" checked={filter.onlyMine} onChange={event => onChange({ ...filter, onlyMine: event.target.checked })} /><span>Bara mina bokningar</span></label>
        <label className="wt-check"><input type="checkbox" checked={filter.onlyPending} onChange={event => onChange({ ...filter, onlyPending: event.target.checked })} /><span>Bara väntande</span></label>
      </fieldset>
      <fieldset>
        <legend>Tider</legend>
        <div className="bk-times">
          <label>Från
            <select value={filter.range.start} onChange={event => onChange({ ...filter, range: { start: Number(event.target.value), end: Math.max(filter.range.end, Number(event.target.value) + 2) } })}>
              {hourOptions.slice(0, 23).map(hour => <option key={hour} value={hour}>{String(hour).padStart(2, "0")}:00</option>)}
            </select>
          </label>
          <label>Till
            <select value={filter.range.end} onChange={event => onChange({ ...filter, range: { start: Math.min(filter.range.start, Number(event.target.value) - 2), end: Number(event.target.value) } })}>
              {hourOptions.slice(2).map(hour => <option key={hour} value={hour}>{String(hour).padStart(2, "0")}:00</option>)}
            </select>
          </label>
        </div>
        <div className="cal-chips">
          {[["Hela dygnet", 0, 24], ["06–24", 6, 24], ["Dag 08–18", 8, 18], ["Kväll 16–23", 16, 23]].map(([label, start, end]) => (
            <button key={label as string} type="button" aria-pressed={filter.range.start === start && filter.range.end === end} onClick={() => onChange({ ...filter, range: { start: start as number, end: end as number } })}>{label}</button>
          ))}
        </div>
        <button type="button" className="wt-button secondary small cal-filter-reset" onClick={() => onChange(emptyFilter)} disabled={activeFilterCount(filter) === 0}>Återställ</button>
      </fieldset>
    </div>
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
  const act = async (name: "cancel_booking" | "decide_booking" | "cancel_booking_series" | "decide_booking_series" | "cancel_booking_group" | "decide_booking_group", approve?: boolean) => {
    if (!client) return;
    if (name === "cancel_booking" && !window.confirm("Avboka den här bokningen?")) return;
    if (name === "cancel_booking_series" && !window.confirm(`Avboka alla ${booking.series_remaining ?? ""} kommande tillfällen i serien?`)) return;
    if (name === "cancel_booking_group" && !window.confirm(`Avboka alla ${booking.group_resources?.length ?? ""} resurser i bokningen?`)) return;
    setBusy(true);
    const decision = approve === undefined ? {} : { approve };
    const params = name.endsWith("_series") ? { target_series_id: booking.series_id, ...decision }
      : name.endsWith("_group") ? { target_group_id: booking.group_id, ...decision }
      : { target_booking_id: booking.id, ...decision };
    const { error: actError } = await client.schema("api").rpc(name, params);
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
        {booking.series_id && <><dt>Serie</dt><dd>Återkommande, {booking.series_remaining} kommande tillfällen</dd></>}
        {booking.group_id && (booking.group_resources?.length ?? 0) > 1 && <><dt>Bokat tillsammans</dt><dd>{booking.group_resources?.join(", ")}</dd></>}
      </dl>
      {error && <p role="alert" className="wt-error">{error}</p>}
      <div className="wt-actions">
        {booking.can_decide && booking.series_id && <button type="button" className="wt-button" disabled={busy} onClick={() => act("decide_booking_series", true)}>Godkänn hela serien</button>}
        {booking.can_decide && booking.series_id && <button type="button" className="wt-button secondary" disabled={busy} onClick={() => act("decide_booking_series", false)}>Neka hela serien</button>}
        {booking.can_decide && booking.group_id && <button type="button" className="wt-button" disabled={busy} onClick={() => act("decide_booking_group", true)}>Godkänn allt som väntar</button>}
        {booking.can_decide && booking.group_id && <button type="button" className="wt-button secondary" disabled={busy} onClick={() => act("decide_booking_group", false)}>Neka allt som väntar</button>}
        {booking.can_decide && !booking.series_id && !booking.group_id && <button type="button" className="wt-button" disabled={busy} onClick={() => act("decide_booking", true)}>Godkänn</button>}
        {booking.can_decide && !booking.series_id && !booking.group_id && <button type="button" className="wt-button secondary" disabled={busy} onClick={() => act("decide_booking", false)}>Neka</button>}
        {booking.can_cancel && <button type="button" className="wt-button secondary" disabled={busy} onClick={() => act("cancel_booking")}>{booking.series_id ? "Avboka detta tillfälle" : (booking.group_resources?.length ?? 0) > 1 ? `Avboka ${booking.resource_name}` : "Avboka"}</button>}
        {booking.can_cancel && booking.group_id && (booking.group_resources?.length ?? 0) > 1 && <button type="button" className="wt-button secondary" disabled={busy} onClick={() => act("cancel_booking_group")}>Avboka alla resurser</button>}
        {booking.can_cancel && booking.series_id && (booking.series_remaining ?? 0) > 1 && <button type="button" className="wt-button secondary" disabled={busy} onClick={() => act("cancel_booking_series")}>Avboka alla kommande</button>}
        <button type="button" className="wt-button secondary" onClick={() => dialog.current?.close()}>Stäng</button>
      </div>
    </dialog>
  );
}
