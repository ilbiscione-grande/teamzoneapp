"use client";

import { useEffect, useRef, useState } from "react";
import { addDays, bookingError, categoryLabels, dateKey, eventOptionLabel, groupResources, isoWeekday, localInstant, timeOf, weekdayLabels, type Organization, type Resource, type SeriesPlan, type TeamEvent } from "../../lib/booking";
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
  /** Count: how many times a series booked. */
  onBooked: (status: string, count?: number) => void;
}) {
  const { client } = useAccount();
  const dialog = useRef<HTMLDialogElement>(null);
  const [date, setDate] = useState(day);
  const [start, setStart] = useState(startTime);
  const [end, setEnd] = useState(endTime);
  const [title, setTitle] = useState("");
  const [notes, setNotes] = useState("");
  const [resourceId, setResourceId] = useState(given?.id ?? "");
  const resource = given ?? org.resources.find(item => item.id === resourceId && item.active) ?? null;
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
    if (!resource) { setError("Välj vad du vill boka."); return; }
    if (repeat) { await series(plan === null); return; }
    const startsAt = localInstant(date, start);
    let endsAt = localInstant(date, end);
    // Past midnight: the end is on the next day.
    if (new Date(endsAt) <= new Date(startsAt)) endsAt = new Date(new Date(endsAt).getTime() + 86400e3).toISOString();
    setBusy(true);
    setError("");
    const { data, error: bookError } = await client.schema("api").rpc("create_booking", {
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

  // First a dry run to show the times and clashes; then the booking.
  const series = async (dryRun: boolean) => {
    if (!client || !resource) return;
    if (weekdays.length === 0) { setError("Välj minst en veckodag."); return; }
    if (end <= start) { setError("En återkommande bokning slutar samma dag: sluttiden behöver vara efter starttiden."); return; }
    setBusy(true);
    setError("");
    const { data, error: seriesError } = await client.schema("api").rpc("create_booking_series", {
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
  const asks = resource?.requires_approval && org.role !== "admin";

  return (
    <dialog ref={dialog} className="bk-dialog" onClose={onClose} aria-labelledby="booking-form-title">
      <form className="wt-form" onSubmit={submit}>
        <h2 id="booking-form-title">{given ? `Boka ${given.name}` : "Boka"}</h2>
        {!given && (
          <label>Vad vill du boka?
            <select value={resourceId} onChange={event => setResourceId(event.target.value)} required>
              <option value="">Välj resurs</option>
              {groupResources(org.resources).map(group => (
                <optgroup key={group.category} label={categoryLabels[group.category]}>
                  {group.items.map(item => <option key={item.id} value={item.id}>{item.name}{item.requires_approval ? " (godkänns)" : ""}</option>)}
                </optgroup>
              ))}
            </select>
          </label>
        )}
        {resource?.requires_approval && org.role !== "admin" && (
          <p className="wt-note">Bokningar av den här resursen godkänns av en administratör.</p>
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
        {error && <p role="alert" className="wt-error">{error}</p>}
        <div className="wt-actions">
          <button type="submit" className="wt-button" disabled={busy || !resource || (plan !== null && free === 0)}>
            {repeat
              ? plan === null ? "Visa tillfällen" : asks ? `Skicka förfrågan för ${free} tillfällen` : `Boka ${free} tillfällen`
              : asks ? "Skicka förfrågan" : "Boka"}
          </button>
          <button type="button" className="wt-button secondary" onClick={() => dialog.current?.close()}>Avbryt</button>
        </div>
      </form>
    </dialog>
  );
}
