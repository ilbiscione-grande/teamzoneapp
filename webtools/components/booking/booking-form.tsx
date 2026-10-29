"use client";

import { useEffect, useRef, useState } from "react";
import { addDays, bookingError, categoryLabels, dateKey, eventOptionLabel, groupResources, isoWeekday, localInstant, timeOf, weekdayLabels, type Organization, type Resource, type SeriesPlan, type TeamEvent } from "../../lib/booking";
import { bookingCommand } from "../../lib/booking-command";
import { useAccount } from "../account";

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
  const [date, setDate] = useState(day);
  const [start, setStart] = useState(startTime);
  const [end, setEnd] = useState(endTime);
  const [title, setTitle] = useState("");
  const [notes, setNotes] = useState("");
  // Several resources at once: all are booked, or none.
  const [selected, setSelected] = useState<string[]>(given ? [given.id] : []);
  const [showMore, setShowMore] = useState(!given);
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
  const [error, setError] = useState("");
  // Recurring: weekdays, every n weeks, until a date; planned before booking.
  const [repeat, setRepeat] = useState(false);
  const [weekdays, setWeekdays] = useState<number[]>(() => [isoWeekday(day)]);
  const [interval, setEveryWeeks] = useState(1);
  const [until, setUntil] = useState(() => addDays(day, 84));
  const [plan, setPlan] = useState<SeriesPlan | null>(null);
  // Any change to what is booked asks for a new plan.
  useEffect(() => { setPlan(null); }, [date, start, end, weekdays, interval, until, resourceId, teamId]);

  useEffect(() => { dialog.current?.showModal(); }, []);

  // Which of the chosen resources are free at the time, checked as you go.
  useEffect(() => {
    if (!client || selected.length === 0 || repeat) { setAvailability({}); return; }
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
    // The activity's own time, which the booking usually follows.
    setDate(dateKey(new Date(chosen.starts_at)));
    setStart(timeOf(chosen.starts_at));
    setEnd(timeOf(chosen.ends_at));
    if (!title) setTitle(chosen.title);
  };

  const submit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!client) return;
    if (selected.length === 0) { setError("Välj vad du vill boka."); return; }
    if (many) { await group(); return; }
    if (!resource) { setError("Välj vad du vill boka."); return; }
    if (repeat) { await series(plan === null); return; }
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
    });
    setBusy(false);
    if (groupError) {
      setError(groupError.message === "resource_busy" ? "Någon av resurserna är upptagen den tiden. Ingen av dem har bokats." : bookingError(groupError));
      return;
    }
    const result = data as { pending: number };
    onBooked(result.pending > 0 ? "pending" : "confirmed", selected.length, "resources");
  };

  // First a dry run to show the times and clashes; then the booking.
  const series = async (dryRun: boolean) => {
    if (!client || !resource) return;
    if (weekdays.length === 0) { setError("Välj minst en veckodag."); return; }
    if (end <= start) { setError("En återkommande bokning slutar samma dag: sluttiden behöver vara efter starttiden."); return; }
    setBusy(true);
    setError("");
    const { data, error: seriesError } = await bookingCommand(client, "create_booking_series", {
      target_resource_id: resource.id,
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
    });
    setBusy(false);
    if (seriesError) { setError(bookingError(seriesError)); return; }
    const result = data as SeriesPlan;
    if (dryRun) { setPlan(result); return; }
    onBooked(result.status, result.created);
  };

  const free = plan ? plan.times.filter(time => !time.clash).length : 0;
  const clashes = plan ? plan.times.filter(time => time.clash) : [];
  const chosen = org.resources.filter(item => selected.includes(item.id));
  const asks = chosen.some(item => item.requires_approval) && org.role !== "admin";
  const busyChosen = chosen.filter(item => availability[item.id]);

  return (
    <dialog ref={dialog} className="bk-dialog" onClose={onClose} aria-labelledby="booking-form-title">
      <form className="wt-form" onSubmit={submit}>
        <h2 id="booking-form-title">{given && !many ? `Boka ${given.name}` : "Boka"}</h2>
        {showMore ? (
          <fieldset className="bk-pick">
            <legend>Vad vill du boka?</legend>
            {groupResources(org.resources).map(category => (
              <div key={category.category} className="bk-pick-group">
                <span>{categoryLabels[category.category]}</span>
                {category.items.map(item => (
                  <label key={item.id} className="wt-check" data-busy={availability[item.id] === true}>
                    <input type="checkbox" checked={selected.includes(item.id)} onChange={() => toggle(item.id)} disabled={repeat && !selected.includes(item.id) && selected.length >= 1} />
                    <span>{item.name}{item.requires_approval ? " · godkänns" : ""}{availability[item.id] === true ? " · upptagen" : ""}</span>
                  </label>
                ))}
              </div>
            ))}
            {repeat && <p className="wt-small">Återkommande bokningar gäller en resurs i taget.</p>}
          </fieldset>
        ) : (
          <p className="wt-small">
            {availability[selected[0]] === true && <strong className="wt-error">Upptagen den tiden. </strong>}
            <button type="button" className="wt-link-button" onClick={() => setShowMore(true)}>Boka fler resurser samtidigt</button>
          </p>
        )}
        {asks && (
          <p className="wt-note">{many ? "Några av resurserna godkänns av en administratör. De övriga är bokade direkt." : "Bokningar av den här resursen godkänns av en administratör."}</p>
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
        {!eventId && !many && (
          <label className="wt-check">
            <input type="checkbox" checked={repeat} onChange={event => { setRepeat(event.target.checked); setPlan(null); }} />
            <span>Återkommande, till exempel varje vecka under säsongen</span>
          </label>
        )}
        {repeat && !eventId && !many && (
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
        <label>Anteckning (frivilligt)<textarea value={notes} onChange={event => setNotes(event.target.value)} maxLength={2000} rows={3} /></label>
        {plan && (
          <div className="wt-note bk-plan" role="status">
            <p><strong>{plan.times.length} tillfällen</strong>{clashes.length > 0 ? `, varav ${clashes.length} krockar med befintliga bokningar och hoppas över:` : ", inga krockar."}</p>
            {clashes.length > 0 && (
              <ul>{clashes.slice(0, 8).map(time => <li key={time.starts_at}>{new Date(time.starts_at).toLocaleDateString("sv-SE", { weekday: "short", day: "numeric", month: "short" })} {timeOf(time.starts_at)}</li>)}
                {clashes.length > 8 && <li>och {clashes.length - 8} till</li>}</ul>
            )}
            {asks && <p className="wt-small">Hela serien godkänns av en administratör i ett steg.</p>}
          </div>
        )}
        {busyChosen.length > 0 && !repeat && (
          <p role="alert" className="wt-error">Upptaget den tiden: {busyChosen.map(item => item.name).join(", ")}. Välj en annan tid eller ta bort {busyChosen.length === 1 ? "den" : "dem"}.</p>
        )}
        {error && <p role="alert" className="wt-error">{error}</p>}
        <div className="wt-actions">
          <button type="submit" className="wt-button" disabled={busy || selected.length === 0 || busyChosen.length > 0 || (plan !== null && free === 0)}>
            {many
              ? `Boka ${selected.length} resurser`
              : repeat
              ? plan === null ? "Visa tillfällen" : asks ? `Skicka förfrågan för ${free} tillfällen` : `Boka ${free} tillfällen`
              : asks ? "Skicka förfrågan" : "Boka"}
          </button>
          <button type="button" className="wt-button secondary" onClick={() => dialog.current?.close()}>Avbryt</button>
        </div>
      </form>
    </dialog>
  );
}
