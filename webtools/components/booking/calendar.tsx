"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { dialogBackdropHandlers } from '../../lib/dialog-backdrop';
import { calendarPreferenceKey, parseCalendarPreference, type CalendarView } from '../../lib/calendar-preferences';
import {
  activeFilterCount, addDays, addMinutes, bookingError, bookingSpan, categoryLabels, dateKey, dayLabel, emptyFilter,
  gridPlacement, groupResources, localInstant, matchesFilter, nowFraction, parseFilter, resourcePath, slotAt, statusLabels, weekStart,
  type Booking, type CalendarFilter, type Organization, type Resource,
} from "../../lib/booking";
import { bookingCommand, bookingRevisions } from "../../lib/booking-command";
import { useAccount } from "../account";
import { BookingSeriesPlanEditor } from "./series-plans";
import { BookingEditor } from "./booking-editor";
import { BookingResourcesEditor } from "./booking-resources-editor";
import { BookingResourceEditor } from "./booking-resource-editor";
import { BookingTimeEditor } from "./booking-time-editor";
import { BookingForm } from "./booking-form";
import { BookingActivityLink } from "./booking-activity-link";
import { resourceFamilies } from "../../lib/resource-families";
import "./calendar-layout.css";
import { useCalendarHeight } from "./use-calendar-height";
import { calendarResources, calendarCards } from "../../lib/calendar-resources";
import { calendarLanes } from "../../lib/calendar-lanes";
import { bookingAgenda, calendarWeek } from "../../lib/booking-agenda";

type View = CalendarView;
const HOUR_PX = 52;

/**
 * Physical resources share a day column; weeks show one physical resource or all pitches. Bookings sit on their time; tapping a free time books it.
 */
export function BookingCalendar({ org, prefill, onPrefillUsed, initialBooking }: {
  org: Organization;
  initialBooking?: Booking;
  /** From the app's "Boka resurs": open the form for this team and activity. */
  prefill?: { teamId?: string; eventId: string };
  onPrefillUsed?: () => void;
}) {
  const { client } = useAccount();
  const [view, setView] = useState<View>("day");
  const [day, setDay] = useState(() => dateKey(initialBooking ? new Date(initialBooking.starts_at) : new Date()));
  const families = useMemo(() => resourceFamilies(org.resources), [org.resources]);
  const active = useMemo(() => families.flatMap(group => group.items.map(node => node.resource)).filter(resource => resource.active), [families]);
  const [search, setSearch] = useState("");
  const [bookingSearch, setBookingSearch] = useState("");
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
  const [resourceId, setResourceId] = useState<string>("all-pitches");
  const viewStorageKey = calendarPreferenceKey(org.id);
  const restoredViewKey = useRef('');
  useEffect(()=>{
    if(restoredViewKey.current===viewStorageKey)return;
    restoredViewKey.current=viewStorageKey;
    // An activity or a specific booking opens in its own context, even after its dialog closes.
    if(prefill || initialBooking)return;
    try {
      const saved=parseCalendarPreference(window.localStorage.getItem(viewStorageKey),calendarResources(active,org.resources).map(resource=>resource.id));
      setView(saved.view);setResourceId(saved.resourceId);
    }catch{/* Storage may be unavailable; the calendar still works. */}
  },[viewStorageKey,active,org.resources,prefill,initialBooking]);
  const rememberView = (nextView:View,nextResource=resourceId) => {
    setView(nextView);setResourceId(nextResource);
    try {window.localStorage.setItem(viewStorageKey,JSON.stringify({view:nextView,resourceId:nextResource}));}catch{/* Storage off. */}
  };
  const [bookings, setBookings] = useState<Booking[] | null>(null);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [draft, setDraft] = useState<{ resource: Resource | null; day: string; start: string; end: string; teamId?: string; eventId?: string } | null>(
    () => prefill ? { resource: null, day: dateKey(new Date()), start: "18:00", end: "19:30", teamId: prefill.teamId, eventId: prefill.eventId } : null);
  const [open, setOpen] = useState<Booking | null>(initialBooking ?? null);
  const [now, setNow] = useState(() => new Date());
  const scroller = useRef<HTMLDivElement>(null);
  const loadSequence = useRef(0);
  const frameHeight = useCalendarHeight(scroller,view);

  // The minute line moves with the clock.
  useEffect(() => { const timer = setInterval(() => setNow(new Date()), 60_000); return () => clearInterval(timer); }, []);

  const days = view === "day" ? [day] : Array.from({ length: 7 }, (_, index) => addDays(weekStart(day), index));
  const range = { from: localInstant(days[0], "00:00"), to: localInstant(addDays(days[days.length - 1], 1), "00:00") };

  const load = useCallback(async () => {
    if (!client) return;
    const sequence = ++loadSequence.current;
    setBookings(null);
    setError("");
    const { data, error: loadError } = await client.schema("api").rpc("list_bookings", { target_organization_id: org.id, range_start: range.from, range_end: range.to });
    if (sequence !== loadSequence.current) return;
    if (loadError) { setError(bookingError(loadError)); setBookings([]); return; }
    setError("");
    setBookings(data as Booking[]);
  }, [client, org.id, range.from, range.to]);

  useEffect(() => { void load(); return () => { loadSequence.current++; }; }, [load]);

  // Open at the working day rather than at six in the morning.
  useEffect(() => {
    const target = Math.max((Math.min(new Date().getHours(), 17) - 1 - filter.range.start), 0) * HOUR_PX;
    scroller.current?.scrollTo({ top: target });
  }, [view, filter.range.start]);

  const selectedResources = filter.resourceIds === null ? active : active.filter(resource => filter.resourceIds!.includes(resource.id));
  const shown = selectedResources.filter(resource => view === "list" || resourcePath(resource, org.resources).toLocaleLowerCase("sv").includes(search.trim().toLocaleLowerCase("sv")));
  const agenda = bookingAgenda(bookings ?? [], org.resources, days, filter, bookingSearch);
  const selectedFamily = filter.resourceIds === null ? "" : families.find(group => {
    const ids = group.items.filter(node => node.resource.active).map(node => node.resource.id);
    return ids.length === selectedResources.length && ids.every(id => selectedResources.some(resource => resource.id === id));
  })?.root.id ?? "custom";
  // Teams to filter by: yours, and those with bookings in view.
  const teams = new Map<string, string>(org.teams.map(team => [team.team_id, team.name]));
  for (const booking of bookings ?? []) if (booking.team_id && booking.team_name) teams.set(booking.team_id, booking.team_name);
  const allPitches = view === "week" && resourceId === "all-pitches";
  const physical = calendarResources(active,org.resources);
  const cards = calendarCards(bookings ?? [],org.resources);
  const weekResource = physical.find(resource => resource.id === resourceId) ?? physical[0];
  const columns: { key: string; resource: Resource; day: string; title: string; subtitle: string }[] = view === "day"
    ? calendarResources(shown,org.resources).map(resource => ({ key: resource.id, resource, day, title: resource.name, subtitle: categoryLabels[resource.category] }))
    : weekResource ? days.map(item => {
      const [y, m, d] = item.split("-").map(Number);
      const date = new Date(y, m - 1, d);
      return { key: item, resource: weekResource, day: item, title: date.toLocaleDateString("sv-SE", { weekday: "short" }), subtitle: date.toLocaleDateString("sv-SE", { day: "numeric", month: "short" }) };
    }) : [];

  const columnLayouts = new Map(columns.map(column => [column.key, calendarLanes(cards.filter(card => allPitches ? card.resource.category === "pitch" : card.resource.id === column.resource.id).flatMap(card => { const place = gridPlacement(card.booking.starts_at,card.booking.ends_at,column.day,filter.range); return place ? [{...place,id:card.id,booking:card.booking,card}] : []; }))]));

  const step = (direction: number) => setDay(addDays(day, direction * (view === "day" ? 1 : 7)));
  const title = view === "day"
    ? dayLabel(day)
    : `Vecka ${calendarWeek(days[0])} · ${new Date(range.from).toLocaleDateString("sv-SE", { day: "numeric", month: "short" })} – ${new Date(localInstant(days[6], "12:00")).toLocaleDateString("sv-SE", { day: "numeric", month: "short" })}`;

  const tap = (event: React.MouseEvent<HTMLDivElement>, resource: Resource | null, columnDay: string) => {
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
          <button type="button" role="tab" aria-selected={view === "day"} onClick={() => rememberView("day")}>Dag</button>
          <button type="button" role="tab" aria-selected={view === "week"} onClick={() => rememberView("week")}>Vecka</button>
          <button type="button" role="tab" aria-selected={view === "list"} onClick={() => rememberView("list")}>Lista</button>
        </div>
      </div>
      <div className="cal-filters" data-view={view}>
        {view !== "week" && <div className="bk-resource-controls">
          <label><span className="cal-control-label">Resursgrupp</span><select value={selectedFamily} onChange={event => {
            const group = families.find(item => item.root.id === event.target.value);
            setFilter({ ...filter, resourceIds: group ? group.items.filter(node => node.resource.active).map(node => node.resource.id) : null });
            setSearch("");
          }}><option value="">Alla resurser</option>{selectedFamily === "custom" && <option value="custom" disabled>Eget urval från filter</option>}{families.filter(group => group.items.some(node => node.resource.active)).map(group => <option key={group.root.id} value={group.root.id}>{group.root.name}{group.items.length > 1 ? " med delar" : ""}{group.root.location ? ` · ${group.root.location}` : ""}</option>)}</select></label>
          {view === "list" ? <label><span className="cal-control-label">Sök bokning</span><input type="search" value={bookingSearch} onChange={event => setBookingSearch(event.target.value)} placeholder="Sök bokning…" /></label> : <label><span className="cal-control-label">Sök resurs</span><input type="search" value={search} onChange={event => setSearch(event.target.value)} placeholder="Sök resurs…" /></label>}
          <span className="cal-control-label" role="status">{calendarResources(shown,org.resources).length} resurskolumner visas.</span>
        </div>}
        <button type="button" className="wt-button secondary small cal-filter-button" aria-expanded={filtering} onClick={() => setFiltering(!filtering)}>
          <svg aria-hidden="true" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M3 6h18M3 12h18M3 18h18"/><path d="M8 3v6M16 9v6M10 15v6"/></svg><span className="cal-filter-label">Filter</span>{activeFilterCount(filter) > 0 ? ` (${activeFilterCount(filter)})` : ""}
        </button>
        {view === "week" && (
          <label className="cal-resource"><span className="cal-control-label">Resurs</span>
            <select value={resourceId === "all-pitches" ? "all-pitches" : weekResource?.id} onChange={event => { rememberView(view,event.target.value); if (event.target.value === "all-pitches") setFilter({...filter,resourceIds:null}); }}>
              <option value="all-pitches">Alla planer och plandelar</option>
              {groupResources(physical.map(resource=>({...resource,active:true}))).map(group => (
                <optgroup key={group.category} label={categoryLabels[group.category]}>
                  {group.items.map(resource => <option key={resource.id} value={resource.id}>{resourcePath(resource, org.resources)}</option>)}
                </optgroup>
              ))}
            </select>
          </label>
        )}
        <details className="cal-help">
          <summary aria-label="Hjälp med kalendern" title="Hjälp med kalendern">?</summary>
          <div className="cal-help-content">
            <p>{view === "list" ? "Öppna en bokning för att granska eller ändra. Välj Dag eller Vecka för att boka en ledig tid." : "Tryck på en bokning för att öppna den, eller på en ledig tid för att boka."}</p>
            {view !== "week" && <p>{calendarResources(shown,org.resources).length} resurskolumner visas. Plandelar samlas under sin plan.</p>}
            {allPitches && <p>Varje fysisk plan samlar sina delar. Bokningskortet visar omfattningen. Delar som bokats tillsammans för samma tid visas som ett kort. Samtidiga bokningar visas sida vid sida. Tomt utrymme betyder inte att alla planer är lediga; välj resurs när du bokar. Övriga filter tonar ned bokningar utan att dölja dem.</p>}
          </div>
        </details>
      </div>
      {filtering && (
        <FilterPanel org={org} filter={filter} listMode={view === "list"} teams={[...teams.entries()].sort((a, b) => a[1].localeCompare(b[1], "sv"))} onChange={setFilter} />
      )}

      {view === "day" && shown.length === 0 && <p className="wt-note">Inga resurser matchar urvalet. Byt resursgrupp, ändra sökningen eller välj resurser under Filter.</p>}
      {notice && <p className="wt-note" role="status">{notice}</p>}
      {error && <p className="wt-error" role="alert">{error}</p>}

      {view === "list" ? <section className="bk-agenda" aria-label="Veckans bokningar" aria-busy={bookings === null}>
        <div className="bk-panel-heading">
          <h3>Bokningar i vald vecka</h3>
          {(activeFilterCount(filter) > 0 || bookingSearch.trim()) && <button type="button" className="wt-link-button" onClick={() => { setFilter(emptyFilter); setBookingSearch(""); setSearch(""); }}>Rensa urval och sökning</button>}
        </div>
        <p className="wt-small" role="status">{bookings === null ? "Hämtar bokningar…" : error ? "Bokningarna kunde inte hämtas." : `${new Set(agenda.flatMap(group => group.bookings.map(booking => booking.id))).size} resursbokningar visas · ${String(filter.range.start).padStart(2, "0")}:00–${String(filter.range.end).padStart(2, "0")}:00${activeFilterCount(filter) > 0 || bookingSearch.trim() ? " · filtrerat urval" : ""}`}</p>
        {bookings !== null && !error && agenda.length === 0 && <p className="wt-note">{activeFilterCount(filter) > 0 || bookingSearch.trim() ? "Inga bokningar matchar urvalet denna vecka. Rensa urvalet eller välj en annan vecka." : "Inga bokningar denna vecka inom visade tider. Välj en annan vecka eller kontrollera tiderna under Filter."}</p>}
        {bookings !== null && !error && agenda.map(group => <section key={group.day} className="bk-agenda-day" aria-label={dayLabel(group.day)}>
          <h4>{dayLabel(group.day)}</h4>
          <ul>{group.bookings.map(booking => <li key={booking.id}>
            <button type="button" className="bk-agenda-booking" data-status={booking.status} onClick={() => setOpen(booking)}>
              <span className="bk-agenda-time">{bookingSpan(booking.starts_at, booking.ends_at)}{dateKey(new Date(booking.starts_at)) !== group.day && <small>Påbörjad tidigare</small>}{dateKey(new Date(Date.parse(booking.ends_at) - 1)) > group.day && <small>Fortsätter efter denna dag</small>}</span>
              <span className="bk-agenda-info"><strong>{booking.title || booking.event_title || "Bokning"}</strong><span>{resourcePath(org.resources.find(resource => resource.id === booking.resource_id)!, org.resources)}</span><span>{[booking.team_name, booking.is_mine ? "Du" : booking.booked_by_name].filter(Boolean).join(" · ")}</span></span>
              <span className="bk-agenda-status">{statusLabels[booking.status]}<small>Öppna bokning →</small></span>
            </button>
          </li>)}</ul>
        </section>)}
      </section> : <>
      <div className="cal-frame" ref={scroller} style={{maxHeight:frameHeight}} aria-busy={bookings === null}>
        <div className="cal-grid" style={{ gridTemplateColumns: `56px ${columns.map(column => `minmax(${Math.max(allPitches ? 220 : view === "day" ? 150 : 110,(columnLayouts.get(column.key)?.[0]?.lanes ?? 1) * 120)}px, 1fr)`).join(" ")}` }}>
          <div className="cal-corner" />
          {columns.map(column => (
            <div key={column.key} className="cal-head" data-today={column.day === dateKey(now) && view === "week"}>
              <strong title={allPitches ? "Alla planer och plandelar" : resourcePath(column.resource, org.resources)}>{column.title}</strong>
              <span>{view === "day" && column.resource.parent_resource_id ? `${org.resources.find(item => item.id === column.resource.parent_resource_id)?.name ?? "Delresurs"} · ` : ""}{column.subtitle}{column.resource.requires_approval && view === "day" ? " · godkänns" : ""}</span>
            </div>
          ))}
          <div className="cal-hours" style={{ height: hours.length * HOUR_PX }}>
            {hours.map(hour => <span key={hour} style={{ top: (hour - filter.range.start) * HOUR_PX }}>{String(hour).padStart(2, "0")}:00</span>)}
          </div>
          {columns.map(column => {
            const line = nowFraction(column.day, now, filter.range);
            const arranged = columnLayouts.get(column.key)!;
            return (
              <div
                key={column.key}
                className="cal-column"
                style={{ height: hours.length * HOUR_PX }}
                data-past={new Date(localInstant(addDays(column.day, 1), "00:00")) <= now}
                onClick={event => { if (event.target === event.currentTarget) tap(event, allPitches || !column.resource.active ? null : column.resource, column.day); }}
                role="presentation"
              >
                {line !== null && <div className="cal-now" style={{ top: `${line * 100}%` }} aria-hidden="true" />}
                {arranged.map(({item: place,lane,lanes}) => {
                  const booking = place.booking;
                  const card = place.card;
                  const cardTitle = `${card.resource.name} · ${card.label} · ${bookingSpan(booking.starts_at,booking.ends_at)} · ${booking.title || "Bokning"}`;
                  return (
                    <button
                      key={booking.id}
                      type="button"
                      className="cal-booking"
                      data-status={booking.status}
                      data-mine={booking.is_mine}
                      data-cut-top={place.cutTop}
                      data-cut-bottom={place.cutBottom}
                      data-dimmed={!card.bookings.some(item=>matchesFilter(item,filter))}
                      style={{ top: `${place.top * 100}%`, height: `${place.height * 100}%`, ...{left:`calc(${lane * 100 / lanes}% + 3px)`,right:"auto",width:`calc(${100 / lanes}% - 6px)`} }}
                      onClick={() => setOpen(booking)}
                      title={cardTitle}
                      aria-label={`${card.resource.name}, ${card.label}, ${bookingSpan(booking.starts_at, booking.ends_at)} ${booking.title ?? "Bokad"}${booking.status === "pending" ? ", väntar på godkännande" : ""}`}
                    >
                      {allPitches && <strong>{card.resource.name}</strong>}
                      {card.resource.category === "pitch" && <span className="cal-booking-time">{card.coverage && <svg width="22" height="18" viewBox="0 0 22 18" aria-hidden="true" style={{verticalAlign:"middle",marginRight:4}}>{["A1","B1","A2","B2"].map((key,index)=><rect key={key} x={index%2*11} y={Math.floor(index/2)*9} width="10" height="8" fill={card.coverage!.includes(key)?"#246741":"#dce2e5"} />)}</svg>}{card.label}</span>}
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
      </>}

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
      {open && <BookingDetails org={org} resources={org.resources} booking={open} onClose={() => setOpen(null)} onChanged={() => { setOpen(null); void load(); }} />}
    </section>
  );
}

/** Which resources, teams' bookings, hours and bookings the calendar shows. */
function FilterPanel({ org, filter, teams, onChange, listMode }: {
  org: Organization;
  filter: CalendarFilter;
  teams: [string, string][];
  onChange: (next: CalendarFilter) => void;
  listMode: boolean;
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
        <p className="wt-small">{listMode ? "Listan visar bara bokningar som matchar urvalet. Dag- och veckokalendern visar även övriga bokningar nedtonade." : "Andra bokningar tonas ner, så att du ser att tiden är upptagen."}</p>
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

/** A booking's details with cancel, approve and decline. */
export function BookingDetails({ booking, org, resources, onClose, onChanged }: { booking: Booking; org: Organization; resources: Resource[]; onClose: () => void; onChanged: () => void }) {
  const { client } = useAccount();
  const dialog = useRef<HTMLDialogElement>(null);
  const backdrop = useMemo(dialogBackdropHandlers,[]);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [editing, setEditing] = useState(false);
  useEffect(() => { dialog.current?.showModal(); }, []);
  const act = async (name: "cancel_booking" | "decide_booking" | "cancel_booking_series" | "decide_booking_series" | "cancel_booking_group" | "decide_booking_group", approve?: boolean) => {
    if (!client || busy || editing) return;
    if (name === "cancel_booking" && !window.confirm("Avboka den här bokningen?")) return;
    if (name === "cancel_booking_series" && !window.confirm(`Avboka alla ${booking.series_remaining ?? ""} kommande tillfällen i serien?`)) return;
    if (name === "cancel_booking_group" && !window.confirm(`Avboka alla ${booking.group_resources?.length ?? ""} resurser i bokningen?`)) return;
    setBusy(true);
    const decision = approve === undefined ? {} : { approve };
    const params = name.endsWith("_series") ? { target_series_id: booking.series_id, ...decision }
      : name.endsWith("_group") ? { target_group_id: booking.group_id, ...decision }
      : { target_booking_id: booking.id, ...decision };
    const { error: actError } = await bookingCommand(client, name, params, bookingRevisions(booking, name));
    setBusy(false);
    if (actError) { setError(bookingError(actError)); return; }
    onChanged();
  };
  const start = new Date(booking.starts_at);
  return (
    <dialog ref={dialog} {...backdrop} className="bk-dialog" onClose={onClose} aria-labelledby="booking-details-title">
      <h2 id="booking-details-title">{booking.title ?? booking.resource_name}</h2>
      <details className="bk-resource-details" open={!editing}>
      <summary>Bokningsuppgifter</summary>
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
      </details>
      {!booking.event_id && <p className="wt-small">Fristående bokning utan aktivitet.</p>}
      {booking.event_id && <p className="wt-note">Kopplad till {booking.event_title || "en aktivitet"}.{!editing && " I huvudflödet för tid och resurser följer aktivitetens bokningar med och behåller sina tidsmarginaler. Förhandsvisningen visar vad som påverkas."}</p>}
      {!editing && <BookingActivityLink booking={booking} org={org} onChanged={onChanged} />}
      {booking.can_cancel && Date.parse(booking.starts_at) > Date.now() && <BookingEditor booking={booking} resources={resources} onChanged={onChanged} onOpenChange={setEditing} />}
      {!editing && (booking.series_id || booking.resource_event_series) && (booking.is_mine || booking.can_cancel) && (!booking.event_id || booking.can_move_event) && <details className="bk-resource-details"><summary>Hantera återkommande bokningar</summary><BookingSeriesPlanEditor bookingId={booking.id} resources={resources} onChanged={onChanged} /></details>}
      {!editing && booking.can_cancel && <details className="bk-resource-details"><summary>Fler ändringsalternativ</summary><p className="wt-small">Använd dessa om du bara vill ändra vissa resursbokningar eller deras tidsmarginaler mot aktiviteten.</p>
      {Date.parse(booking.starts_at) > Date.now() && <BookingResourcesEditor booking={booking} resources={resources} onChanged={onChanged} />}
      {Date.parse(booking.starts_at) > Date.now() && <BookingResourceEditor booking={booking} resources={resources} onChanged={onChanged} />}
      <BookingTimeEditor booking={booking} onChanged={onChanged} />
      </details>}
      {error && <p role="alert" className="wt-error">{error}</p>}
      {!editing && <div className="wt-actions">
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
      </div>}
    </dialog>
  );
}
