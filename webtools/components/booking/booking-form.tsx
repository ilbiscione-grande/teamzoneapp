"use client";

import { useEffect, useRef, useState } from "react";
import { bookingError, dateKey, eventOptionLabel, localInstant, timeOf, type Organization, type Resource, type TeamEvent } from "../../lib/booking";
import { useAccount } from "../account";

/** Book a resource: time, a title and, with TeamZone, a team and activity. */
export function BookingForm({ org, resource, day, onClose, onBooked }: {
  org: Organization;
  resource: Resource;
  day: string;
  onClose: () => void;
  onBooked: (status: string) => void;
}) {
  const { client } = useAccount();
  const dialog = useRef<HTMLDialogElement>(null);
  const [date, setDate] = useState(day);
  const [start, setStart] = useState("18:00");
  const [end, setEnd] = useState("19:30");
  const [title, setTitle] = useState("");
  const [notes, setNotes] = useState("");
  const [teamId, setTeamId] = useState("");
  const [eventId, setEventId] = useState("");
  const [events, setEvents] = useState<TeamEvent[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => { dialog.current?.showModal(); }, []);

  // A team's coming activities, to attach the booking to.
  useEffect(() => {
    setEventId("");
    setEvents([]);
    if (!client || !teamId) return;
    client.schema("api").rpc("list_booking_team_events", { target_organization_id: org.id, target_team_id: teamId })
      .then(({ data }) => setEvents((data as TeamEvent[]) ?? []));
  }, [client, org.id, teamId]);

  const chooseEvent = (id: string) => {
    setEventId(id);
    const chosen = events.find(item => item.event_id === id);
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

  return (
    <dialog ref={dialog} className="bk-dialog" onClose={onClose} aria-labelledby="booking-form-title">
      <form className="wt-form" onSubmit={submit}>
        <h2 id="booking-form-title">Boka {resource.name}</h2>
        {resource.requires_approval && org.role !== "admin" && (
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
        <label>Datum<input type="date" value={date} onChange={event => setDate(event.target.value)} required /></label>
        <div className="bk-times">
          <label>Från<input type="time" value={start} onChange={event => setStart(event.target.value)} required step={300} /></label>
          <label>Till<input type="time" value={end} onChange={event => setEnd(event.target.value)} required step={300} /></label>
        </div>
        <label>Rubrik (frivilligt)<input value={title} onChange={event => setTitle(event.target.value)} maxLength={160} placeholder="T.ex. Träning P2012" /></label>
        <label>Anteckning (frivilligt)<textarea value={notes} onChange={event => setNotes(event.target.value)} maxLength={2000} rows={3} /></label>
        {error && <p role="alert" className="wt-error">{error}</p>}
        <div className="wt-actions">
          <button type="submit" className="wt-button" disabled={busy}>{resource.requires_approval && org.role !== "admin" ? "Skicka förfrågan" : "Boka"}</button>
          <button type="button" className="wt-button secondary" onClick={() => dialog.current?.close()}>Avbryt</button>
        </div>
      </form>
    </dialog>
  );
}
