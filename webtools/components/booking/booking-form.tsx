"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { dialogBackdropHandlers } from '../../lib/dialog-backdrop';
import { resourcePath, addDays, bookingError, categoryLabels, dateKey, eventOptionLabel, groupResources, isoWeekday, localInstant, timeOf, weekdayLabels, type Organization, type Resource, type SeriesOverride, type SeriesPlan, type TeamEvent } from "../../lib/booking";
import { bookingCommand } from "../../lib/booking-command";
import { useAccount } from "../account";
import { pitchOptions, dispositionLabel } from "../../lib/pitch-options";
import { SeriesPreview } from "./series-preview";
import { BookingAlternatives } from "./booking-alternatives";

/** Book a resource: time, a title and, with TeamZone, a team and activity. */
export function BookingForm({ org, resource: given, day, startTime = "18:00", endTime = "19:30", teamId: givenTeam, eventId: givenEvent, onClose, onBooked }: {
  org: Organization;
  /** Null when coming from the app: the resource is chosen in the form. */
  resource: Resource | null;
  /** From the app: the team and activity the booking is for. */
  teamId?: string;
  eventId?: string;
  day: string;
  /** From the slot tapped in the calendar. */
  startTime?: string;
  endTime?: string;
  onClose: () => void;
  /** Count: how many times a series, or how many resources a group, booked. */
  onBooked: (status: string, count?: number, kind?: "times" | "resources") => void;
}) {
  const { client } = useAccount();
  const dialog = useRef<HTMLDialogElement>(null);
  const backdrop = useMemo(dialogBackdropHandlers,[]);
  const [date, setDate] = useState(day);
  const [start, setStart] = useState(startTime);
  const [end, setEnd] = useState(endTime);
  const [title, setTitle] = useState("");
  const [notes, setNotes] = useState("");
  // Several resources at once: all are booked, or none.
  const [selected, setSelected] = useState<string[]>(given ? [given.id] : []);
  const [pitchRoot, setPitchRoot] = useState(given?.id ?? "");
  const options = pitchOptions(org.resources.find(item => item.id === pitchRoot), org.resources);
  const option = options.find(item => item.resourceIds.length === selected.length && item.resourceIds.every(id => selected.includes(id)));
  const [showMore, setShowMore] = useState(false);
  const [availability, setAvailability] = useState<Record<string, boolean>>({});
  const resourceId = selected.length === 1 ? selected[0] : "";
  const resource = selected.length === 1 ? org.resources.find(item => item.id === selected[0] && item.active) ?? null : null;
  const many = selected.length > 1;
  const toggle = (id: string) => setSelected(current => current.includes(id) ? current.filter(item => item !== id) : [...current, id].slice(0, 10));
  const [teamId, setTeamId] = useState(givenTeam && org.teams.some(team => team.team_id === givenTeam) ? givenTeam : "");
  const [eventId, setEventId] = useState("");
  const [pendingEvent, setPendingEvent] = useState(givenEvent ?? "");
  const [events, setEvents] = useState<TeamEvent[]>([]);
  const [busy, setBusy] = useState(false);
  const [reviewing, setReviewing] = useState(false);
  const [error, setError] = useState("");
  // Recurring: weekdays, every n weeks, until a date; planned before booking.
  const [repeat, setRepeat] = useState(false);
  const [weekdays, setWeekdays] = useState<number[]>(() => [isoWeekday(day)]);
  const [interval, setEveryWeeks] = useState(1);
  const [until, setUntil] = useState(() => addDays(day, 84));
  const [plan, setPlan] = useState<SeriesPlan | null>(null);
  const [overrides, setOverrides] = useState<SeriesOverride[]>([]);
  const seriesRequest = useRef(0);
  const seriesPending = useRef(false);
  // Metadata changes still require a fresh server plan, but retain per-date choices.
  useEffect(() => { seriesRequest.current++; setPlan(null); if (seriesPending.current) { seriesPending.current=false; setBusy(false); } }, [date, start, end, weekdays, interval, until, selected, teamId, title, notes, repeat]);
  // Per-date choices belong to this schedule and resource selection only.
  useEffect(() => { setOverrides([]); }, [date, start, end, weekdays, interval, until, selected, repeat]);
  useEffect(() => () => { seriesRequest.current++; }, []);
  useEffect(() => { setReviewing(false); }, [selected, date, start, end, teamId, eventId, title, notes, repeat]);

  useEffect(() => { dialog.current?.showModal(); }, []);

  // Which of the chosen resources are free at the time, checked as you go.
  useEffect(() => {
    if (!client || selected.length === 0 || repeat || !date || !start || !end) { setAvailability({}); return; }
    const startsAt = localInstant(date, start);
    let endsAt = localInstant(date, end);
    if (new Date(endsAt) <= new Date(startsAt)) endsAt = new Date(new Date(endsAt).getTime() + 86400e3).toISOString();
    if (new Date(endsAt) <= new Date()) { setAvailability({}); return; }
    let current = true;
    const timer = setTimeout(() => {
      client.schema("api").rpc("create_booking_group", {
        target_resource_ids: selected, booking_starts_at: startsAt, booking_ends_at: endsAt,
        booking_title: null, booking_notes: null, target_team_id: null, target_event_id: null, dry_run: true,
      }).then(({ data }) => {
        if (!current || !data) return;
        setAvailability(Object.fromEntries((data as { items: { resource_id: string; busy: boolean }[] }).items.map(item => [item.resource_id, item.busy])));
      });
    }, 300);
    return () => { current = false; clearTimeout(timer); };
  }, [client, selected, date, start, end, repeat]);

  // A team's coming activities, to attach the booking to.
  useEffect(() => {
    setEventId("");
    setEvents([]);
    if (!client || !teamId) return;
    client.schema("api").rpc("list_booking_team_events", { target_organization_id: org.id, target_team_id: teamId })
      .then(({ data }) => setEvents((data as TeamEvent[]) ?? []));
  }, [client, org.id, teamId]);

  // From the app: the activity is chosen once the team's list is in.
  useEffect(() => {
    if (!pendingEvent || events.length === 0) return;
    if (events.some(item => item.event_id === pendingEvent)) chooseEvent(pendingEvent, events);
    setPendingEvent("");
  }, [events, pendingEvent]);

  const chooseEvent = (id: string, list = events) => {
    setEventId(id);
    const chosen = list.find(item => item.event_id === id);
    if (!chosen) return;
    setRepeat(false);
    // The activity's own time, which the booking usually follows.
    setDate(dateKey(new Date(chosen.starts_at)));
    setStart(timeOf(chosen.starts_at));
    setEnd(timeOf(chosen.ends_at));
    if (!title) setTitle(chosen.title);
  };

  const submit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!client || busy) return;
    if (selected.length === 0) { setError("Välj vad du vill boka."); return; }
    if (!repeat && !reviewing) { setError(""); setReviewing(true); return; }
    if (repeat) { await series(plan === null); return; }
    if (many) { await group(); return; }
    if (!resource) { setError("Välj vad du vill boka."); return; }
    const startsAt = localInstant(date, start);
    let endsAt = localInstant(date, end);
    // Past midnight: the end is on the next day.
    if (new Date(endsAt) <= new Date(startsAt)) endsAt = new Date(new Date(endsAt).getTime() + 86400e3).toISOString();
    setBusy(true);
    setError("");
    const { data, error: bookError } = await bookingCommand(client, "create_booking", {
      target_resource_id: resource.id,
      booking_starts_at: startsAt,
      booking_ends_at: endsAt,
      booking_title: title || null,
      booking_notes: notes || null,
      target_team_id: teamId || null,
      target_event_id: eventId || null,
      ...(eventId ? { expected_event_starts_at: events.find(item => item.event_id === eventId)?.starts_at, expected_event_ends_at: events.find(item => item.event_id === eventId)?.ends_at } : {}),
    });
    setBusy(false);
    if (bookError) { setError(bookingError(bookError)); return; }
    onBooked((data as { status: string }).status);
  };

  const group = async () => {
    if (!client) return;
    const startsAt = localInstant(date, start);
    let endsAt = localInstant(date, end);
    if (new Date(endsAt) <= new Date(startsAt)) endsAt = new Date(new Date(endsAt).getTime() + 86400e3).toISOString();
    setBusy(true);
    setError("");
    const { data, error: groupError } = await bookingCommand(client, "create_booking_group", {
      target_resource_ids: selected, booking_starts_at: startsAt, booking_ends_at: endsAt,
      booking_title: title || null, booking_notes: notes || null,
      target_team_id: teamId || null, target_event_id: eventId || null, dry_run: false,
      ...(eventId ? { expected_event_starts_at: events.find(item => item.event_id === eventId)?.starts_at, expected_event_ends_at: events.find(item => item.event_id === eventId)?.ends_at } : {}),
    });
    setBusy(false);
    if (groupError) {
      setError(groupError.message === "resource_busy" ? "Någon resurs eller en överordnad/underordnad del är upptagen, eller ligger utanför sina bokningsbara tider. Ingen av resurserna har bokats." : bookingError(groupError));
      return;
    }
    const result = data as { pending: number };
    onBooked(result.pending > 0 ? "pending" : "confirmed", selected.length, "resources");
  };

  // First a dry run to show the times and clashes; then the booking.
  const series = async (dryRun: boolean, nextOverrides = overrides) => {
    if (!client || selected.length === 0) return;
    if (weekdays.length === 0) { setError("Välj minst en veckodag."); return; }
    if (end <= start) { setError("En återkommande bokning slutar samma dag: sluttiden behöver vara efter starttiden."); return; }
    setBusy(true);
    setError("");
    const request = ++seriesRequest.current;
    seriesPending.current = true;
    const payload = {
      target_resource_ids:selected,
      occurrence_overrides:nextOverrides,
      series_weekdays: [...weekdays].sort(),
      series_interval: interval,
      first_day: date,
      last_day: until,
      start_at: start,
      end_at: end,
      zone: Intl.DateTimeFormat().resolvedOptions().timeZone || "Europe/Stockholm",
      booking_title: title || null,
      booking_notes: notes || null,
      target_team_id: teamId || null,
      dry_run: dryRun,
      ...(!dryRun ? {expected_plan:plan} : {}),
    };
    const { data, error: seriesError } = dryRun
      ? await client.schema("api").rpc("create_booking_multi_series",{payload})
      : await bookingCommand(client,"create_booking_multi_series",payload);
    if (request !== seriesRequest.current) return;
    seriesPending.current = false;
    setBusy(false);
    if (seriesError) { if (seriesError.message === "stale_revision") setPlan(null); setError(bookingError(seriesError)); return; }
    const result = data as SeriesPlan;
    if (dryRun) { setPlan(result); setOverrides(nextOverrides); return; }
    onBooked(result.status, result.created);
  };

  const free = plan ? plan.times.filter(time => !time.clash).length : 0;
  const chosen = org.resources.filter(item => selected.includes(item.id));
  const asks = chosen.some(item => item.requires_approval) && org.role !== "admin";
  const busyChosen = chosen.filter(item => availability[item.id]);

  return (
    <dialog ref={dialog} {...backdrop} className="bk-dialog" onClose={onClose} aria-labelledby="booking-form-title">
      <form className="wt-form" onSubmit={submit}>
        <h2 id="booking-form-title">{reviewing ? "Kontrollera bokningen" : resource && !many ? `Boka ${resource.name}` : "Ny bokning"}</h2>
        <div className="bk-booking-fields" hidden={reviewing}>
        {!givenEvent && <p className="wt-small">Du kan boka utan lag eller aktivitet. I en TeamZone-kopplad organisation kan bokningen kopplas till en aktivitet senare.</p>}
        {showMore ? (
          <fieldset className="bk-pick">
            <legend>Boka flera resurser</legend>
            <p className="wt-small">Välj upp till tio resurser. Alla kontrolleras och bokas tillsammans.</p>
            {groupResources(org.resources).map(category => (
              <div key={category.category} className="bk-pick-group">
                <span>{categoryLabels[category.category]}</span>
                {category.items.map(item => (
                  <label key={item.id} className="wt-check" data-busy={availability[item.id] === true}>
                    <input type="checkbox" checked={selected.includes(item.id)} onChange={() => toggle(item.id)}  />
                    <span>{resourcePath(item, org.resources)}{item.requires_approval ? " · godkänns" : ""}{availability[item.id] === true ? " · upptagen" : ""}</span>
                  </label>
                ))}
              </div>
            ))}
            {repeat && <p className="wt-small">Alla valda resurser bokas tillsammans vid varje ledigt tillfälle. Om någon del är upptagen hoppas hela tillfället över.</p>}
            {selected.length <= 1 && <button type="button" className="wt-link-button" onClick={() => setShowMore(false)}>Visa enkelt resursval</button>}
          </fieldset>
        ) : (
          <div className="bk-single-resource">
            <label>Resurs
              <select value={options.length ? pitchRoot : resourceId} onChange={event => { setPitchRoot(event.target.value); setSelected(event.target.value ? [event.target.value] : []); setError(""); setAvailability({}); }} required>
                <option value="">Välj resurs</option>
                {groupResources(org.resources).map(category => <optgroup key={category.category} label={categoryLabels[category.category]}>
                  {category.items.map(item => <option key={item.id} value={item.id}>{resourcePath(item, org.resources)}{item.requires_approval ? " · kräver godkännande" : ""}</option>)}
                </optgroup>)}
              </select>
            </label>
            {options.length > 0 && <>
              <label>Hur stor del av planen?<select value={option?.id ?? ""} onChange={event => { const next = options.find(item => item.id === event.target.value); if (next) { setSelected(next.resourceIds); setError(""); setAvailability({}); } }} required><option value="" disabled>Välj omfattning</option>{options.map(item => <option key={item.id} value={item.id}>{item.label}</option>)}</select></label>
              <p className="wt-small">A1 och A2 bildar halvplan A. B1 och B2 bildar halvplan B. För ¾-plan väljer du vilken fjärdedel som lämnas ledig. Alla valda delar bokas tillsammans.</p>
            </>}
            <button type="button" className="wt-link-button" onClick={() => { setPitchRoot(""); setShowMore(true); }}>Boka fler resurser samtidigt</button>
          </div>
        )}
        {chosen.filter(item => item.available_from).map(item => (
          <p key={item.id} className="wt-small">{item.name}: disponeras {dispositionLabel(item)} i {item.timezone}. Eventuella veckotider och datumundantag gäller också.</p>
        ))}
        {chosen.filter(item => item.availability?.mode === "weekly" || item.availability?.exceptions.length).map(item => (
          <p key={`hours-${item.id}`} className="wt-small">{item.name} har särskilda bokningsbara tider i {item.timezone}. Hela bokningen måste rymmas inom tiderna.</p>
        ))}
        {chosen.some(item => item.parent_resource_id || org.resources.some(child => child.parent_resource_id === item.id)) && <p className="wt-small">Bokningen spärrar även överordnade och underordnade delar. En helplan och en del av samma plan kan inte bokas tillsammans.</p>}
        {asks && (
          <p className="wt-note">{many && repeat ? "Hela serien skickas för godkännande om någon av de valda resurserna kräver det." : many ? "Några av resurserna godkänns av en administratör. De övriga är bokade direkt." : "Bokningar av den här resursen godkänns av en administratör."}</p>
        )}
        {/* Why there is no team or activity to choose. */}
        {!org.teamzone_club_id && (
          <p className="wt-small">
            {org.role === "admin"
              ? "Vill du boka för ett lag och en aktivitet i TeamZone? Koppla organisationen till klubben under Inställningar."
              : "Organisationen är inte kopplad till TeamZone, så bokningen kan inte gälla ett lag eller en aktivitet."}
          </p>
        )}
        {org.teamzone_club_id && org.teams.length === 0 && (
          <p className="wt-small">Du är inte ledare för något lag i {org.teamzone_club_name}, så bokningen blir din egen.</p>
        )}
        {org.teams.length > 0 && (
          <label>För laget
            <select value={teamId} onChange={event => setTeamId(event.target.value)}>
              <option value="">Inget lag, en egen bokning</option>
              {org.teams.map(team => <option key={team.team_id} value={team.team_id}>{team.name}</option>)}
            </select>
          </label>
        )}
        {teamId && (
          <label>Aktivitet i TeamZone (frivilligt)
            <select value={eventId} onChange={event => chooseEvent(event.target.value)}>
              <option value="">Ingen aktivitet</option>
              {events.map(item => (
                <option key={item.event_id} value={item.event_id}>{eventOptionLabel(item)}</option>
              ))}
            </select>
          </label>
        )}
        <label>{repeat ? "Från och med" : "Datum"}<input type="date" value={date} onChange={event => { setDate(event.target.value); setPlan(null); }} required /></label>
        <div className="bk-times">
          <label>Från<input type="time" value={start} onChange={event => setStart(event.target.value)} required step={300} /></label>
          <label>Till<input type="time" value={end} onChange={event => setEnd(event.target.value)} required step={300} /></label>
        </div>
        {!eventId && (
          <label className="wt-check">
            <input type="checkbox" checked={repeat} onChange={event => { setRepeat(event.target.checked); setPlan(null); }} />
            <span>Återkommande, till exempel varje vecka under säsongen</span>
          </label>
        )}
        {repeat && !eventId && (
          <fieldset className="bk-repeat" onChange={() => setPlan(null)}>
            <legend>Upprepa</legend>
            <div className="bk-weekdays" role="group" aria-label="Veckodagar">
              {weekdayLabels.map((label, index) => (
                <button key={label} type="button" aria-pressed={weekdays.includes(index + 1)} onClick={() => {
                  setPlan(null);
                  setWeekdays(current => current.includes(index + 1) ? current.filter(day => day !== index + 1) : [...current, index + 1]);
                }}>{label}</button>
              ))}
            </div>
            <div className="bk-times">
              <label>Hur ofta
                <select value={interval} onChange={event => setEveryWeeks(Number(event.target.value))}>
                  <option value={1}>Varje vecka</option>
                  <option value={2}>Varannan vecka</option>
                  <option value={3}>Var tredje vecka</option>
                  <option value={4}>Var fjärde vecka</option>
                </select>
              </label>
              <label>Till och med<input type="date" value={until} min={date} max={addDays(date, 366)} onChange={event => setUntil(event.target.value)} required /></label>
            </div>
          </fieldset>
        )}
        <label>Rubrik (frivilligt)<input value={title} onChange={event => setTitle(event.target.value)} maxLength={160} placeholder="T.ex. Träning P2012" /></label>
        <details className="bk-resource-details">
          <summary>{notes ? "Ändra anteckning" : "Lägg till en anteckning"}</summary>
          <label>Anteckning (frivilligt)<textarea value={notes} onChange={event => setNotes(event.target.value)} maxLength={2000} rows={3} /></label>
        </details>
        {repeat && !plan && overrides.length>0 && <section className="wt-note" role="status" aria-label="Behållna datumval">
          <p><strong>{overrides.length===1 ? 'Ditt eget val för ett datum finns kvar.' : `Dina egna val för ${overrides.length} datum finns kvar.`}</strong></p>
          <p>Välj Visa tillfällen för att kontrollera hela serien igen med de uppdaterade uppgifterna. Inget har bokats ännu.</p>
          <button type="button" className="wt-link-button" disabled={busy} onClick={()=>{setOverrides([]);setPlan(null);setError('');}}>Ta bort alla egna datumval</button>
        </section>}
        {plan && <SeriesPreview plan={plan} asks={plan.status==='pending'} org={org} selected={selected} disabled={busy}
          onChoose={alternative=>{void series(true,[...overrides.filter(item=>item.original_starts_at!==alternative.original_starts_at),alternative]);}}
          onReset={original=>{void series(true,overrides.filter(item=>item.original_starts_at!==original));}}
          resources={option ? `${org.resources.find(item => item.id === pitchRoot)?.name} · ${option.label}` : chosen.map(item => resourcePath(item,org.resources)).join(", ")} />}
        </div>
        {reviewing && <section className="wt-note" aria-label="Bokningssammanfattning">
          <p><strong>{title || "Bokning"}{teamId ? ` · ${org.teams.find(team => team.team_id === teamId)?.name ?? ""}` : " · Egen bokning"}</strong></p>
          <p>{option ? `${org.resources.find(item => item.id === pitchRoot)?.name} · ${option.label}` : chosen.map(item => resourcePath(item, org.resources)).join(", ")}</p>
          <p>{date} · {start}–{end}{end <= start ? " (nästa dag)" : ""} · din lokala tid</p>
          <p>{asks ? "Förfrågan skickas för godkännande. Resurser som inte kräver godkännande bokas direkt." : "Bokningen bekräftas direkt när den kan genomföras."}</p>
          <p>{eventId ? `Kopplas till ${events.find(item => item.event_id === eventId)?.title ?? "vald aktivitet"}. Aktivitetens tid ändras inte.` : "Ingen aktivitet är kopplad."}</p>
          {notes && <p>Anteckning: {notes}</p>}
          <p className="wt-small">Inget har bokats ännu. Tillgänglighet och regler kontrolleras igen när du bekräftar.</p>
        </section>}
        {busyChosen.length > 0 && !repeat && (
          <p role="alert" className="wt-error">Upptaget eller utanför resursens bokningsbara tider: {busyChosen.map(item => item.name).join(", ")}. Välj en annan tid eller ta bort {busyChosen.length === 1 ? "den" : "dem"}.</p>
        )}
        {!repeat && !reviewing && resource && selected.length === 1 && <BookingAlternatives key={`${org.id}:${resource.id}:${date}:${start}:${end}`} org={org} resource={resource} date={date} start={start} end={end} disabled={busy} onChoose={alternative => {
          setPitchRoot(alternative.id); setSelected([alternative.id]); setShowMore(false); setError(""); setAvailability({});
        }} />}
        {error && <p role="alert" className="wt-error">{error}</p>}
        <div className="wt-actions">
          <button type="submit" className="wt-button" disabled={busy || selected.length === 0 || busyChosen.length > 0 || (plan !== null && free === 0)}>
            {busy ? repeat ? "Kontrollerar serien…" : "Sparar…" : !repeat && !reviewing ? "Kontrollera bokningen" : repeat
              ? plan === null ? "Visa tillfällen" : plan.status==='pending' ? `Skicka förfrågan för ${free} tillfällen` : `Boka ${free} tillfällen`
              : many ? `Boka ${selected.length} resurser` : asks ? "Skicka förfrågan" : "Bekräfta bokning"}
          </button>
          {reviewing && <button type="button" disabled={busy} className="wt-button secondary" onClick={() => setReviewing(false)}>Ändra uppgifter</button>}
          <button type="button" className="wt-button secondary" onClick={() => dialog.current?.close()}>Avbryt</button>
        </div>
      </form>
    </dialog>
  );
}
