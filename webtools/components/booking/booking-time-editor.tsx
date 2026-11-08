"use client";

import { useState } from "react";
import { type Booking, bookingError, statusLabels } from "../../lib/booking";
import { bookingCommand } from "../../lib/booking-command";
import { useAccount } from "../account";

type Scope = "booking" | "group" | "event" | "series_forward" | "event_forward" | "series_all" | "event_all";
const isEventScope = (scope: Scope) => scope === "event" || scope === "event_forward" || scope === "event_all";
type Plan = {
  conflicts?: { resource_name: string; starts_at: string; reason: string }[];
  timezone?: string;
  events?: { id: string; title: string; old_starts_at: string; old_ends_at: string; starts_at: string; ends_at: string }[];
  event_starts_at: string | null; event_ends_at: string | null;
  bookings: { id: string; resource_name: string; old_starts_at: string; old_ends_at: string;
    starts_at: string; ends_at: string; old_status: Booking["status"]; status: Booking["status"] }[];
};
function inputTime(iso: string) {
  const d = new Date(iso);
  return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
}
const when = (iso: string) => new Date(iso).toLocaleString("sv-SE", { dateStyle: "short", timeStyle: "short" });

/** Server-produced, revision-bound consequences are confirmed before saving. */
export function BookingTimeEditor({ booking, onChanged }: { booking: Booking; onChanged: () => void }) {
  const { client } = useAccount();
  const [open, setOpen] = useState(false);
  const [scope, setScope] = useState<Scope>("booking");
  const [start, setStart] = useState(inputTime(booking.starts_at));
  const [end, setEnd] = useState(inputTime(booking.ends_at));
  const [plan, setPlan] = useState<Plan | null>(null);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  function choose(value: Scope) {
    setScope(value); setPlan(null); setError("");
    setStart(inputTime(isEventScope(value) ? booking.event_starts_at! : booking.starts_at));
    setEnd(inputTime(isEventScope(value) ? booking.event_ends_at! : booking.ends_at));
  }
  function parameters() {
    return { target_booking_id: booking.id, change_scope: scope,
      new_starts_at: new Date(start).toISOString(), new_ends_at: new Date(end).toISOString() };
  }
  async function preview() {
    if (!client) return;
    if (!start || !end || !Number.isFinite(Date.parse(start)) || !Number.isFinite(Date.parse(end)) || Date.parse(end) <= Date.parse(start)) {
      setError("Ange start och slut. Slutet måste vara efter starten."); return;
    }
    if (inputTime(new Date(start).toISOString()) !== start || inputTime(new Date(end).toISOString()) !== end) {
      setError("Klocktiden finns inte vid övergången till sommartid. Välj en annan tid."); return;
    }
    setBusy(true); setError("");
    try {
      const result = await client.schema("api").rpc("preview_booking_time", parameters());
      if (result.error) setError(bookingError(result.error));
      else setPlan(result.data as Plan);
    } catch { setError("Förhandsvisningen kunde inte hämtas. Försök igen."); }
    finally { setBusy(false); }
  }
  async function save() {
    if (!client || !plan) return;
    setBusy(true); setError("");
    try {
      const result = await bookingCommand(client, "reschedule_booking", { ...parameters(), expected_plan: plan });
      if (result.error) {
        setError(bookingError(result.error));
        // A stale snapshot must be reviewed again; a transport retry retains
        // the unchanged plan and command key in bookingCommand.
        if (["stale_revision", "forward_conflicts"].includes(result.error.message)) setPlan(null);
      } else { onChanged(); }
    } catch { setError("Svaret kunde inte hämtas. Försök igen med samma ändring."); }
    finally { setBusy(false); }
  }
  if (!open) return <button type="button" className="wt-button secondary" onClick={() => setOpen(true)}>Ändra tid</button>;
  return <section aria-label="Ändra bokningstid" className="wt-form">
    <h3>Ändra tid</h3>
    <label>Omfattning<select aria-label="Omfattning" value={scope} disabled={busy} onChange={e => choose(e.target.value as Scope)}>
      <option value="booking">Bara {booking.resource_name}</option>
      {booking.group_id && (booking.group_resources?.length ?? 0) > 1 && <option value="group">Alla resurser i bokningsgruppen</option>}
      {booking.event_id && booking.can_move_event && booking.event_starts_at && booking.event_ends_at && <option value="event">Aktiviteten och alla kopplade bokningar</option>}
      {booking.series_id && (booking.series_forward_remaining ?? 0) > 1 && Date.parse(booking.starts_at) > Date.now() && <option value="series_forward">Denna och följande bokningar i serien ({booking.series_forward_remaining} tillfällen)</option>}
      {booking.event_id && booking.can_move_event && (booking.event_forward_remaining ?? 0) > 1 && Date.parse(booking.starts_at) > Date.now() && <option value="event_forward">Denna och följande aktiviteter med alla resurser ({booking.event_forward_remaining} tillfällen)</option>}
      {booking.series_id && (booking.series_upcoming_remaining ?? 0) > 1 && Date.parse(booking.starts_at) > Date.now() && <option value="series_all">Hela den kommande bokningsserien ({booking.series_upcoming_remaining} tillfällen)</option>}
      {booking.event_id && booking.can_move_event && (booking.event_upcoming_remaining ?? 0) > 1 && Date.parse(booking.starts_at) > Date.now() && <option value="event_all">Hela den kommande aktivitetsserien med alla resurser ({booking.event_upcoming_remaining} tillfällen)</option>}
    </select></label>
    <p>{scope === "series_all" ? "Utgå från det valda tillfällets nya tid. Samma tidsförändring görs för hela den kommande bokningsserien, även kommande tillfällen före det valda. Pågående, tidigare och avbokade tillfällen lämnas kvar."
      : scope === "event_all" ? "Utgå från det valda tillfällets nya aktivitetstid. Hela den kommande aktivitetsserien flyttas, även kommande tillfällen före det valda. Alla resursbokningar följer med och marginalerna behålls. Pågående, tidigare, avbokade och arkiverade aktiviteter lämnas kvar."
      : scope === "series_forward" ? "Samma tidsförändring görs för denna och följande kvarvarande bokningar i seriens ordning. Tidigare och avbokade tillfällen lämnas kvar."
      : scope === "event_forward" ? "Ange detta tillfälles nya aktivitetstid. Samma tidsförändring görs för denna och följande planerade aktiviteter. Alla deras resursbokningar följer med och marginalerna behålls."
      : scope === "event" ? "Ange aktivitetens nya tider. Alla kopplade bokningar följer med och deras marginaler behålls."
      : booking.event_id ? "Aktivitetens tid ändras inte. Du ändrar resursens bokningstid och därmed marginalerna mot aktiviteten." : "Bara resursbokningen ändras."}</p>
    {booking.event_id && !booking.can_move_event && <p>Du saknar behörighet att flytta aktiviteten.</p>}
    <label>Ny start<input aria-label="Ny start" type="datetime-local" value={start} disabled={busy} onChange={e => { setStart(e.target.value); setPlan(null); }} /></label>
    <label>Nytt slut<input aria-label="Nytt slut" type="datetime-local" value={end} disabled={busy} onChange={e => { setEnd(e.target.value); setPlan(null); }} /></label>
    <p className="wt-small">Tiderna visas i {Intl.DateTimeFormat().resolvedOptions().timeZone}. {scope.endsWith("_all") ? "Ändringen gäller hela den kommande serien." : scope.endsWith("_forward") ? "Ändringen gäller detta och följande tillfällen." : "Ändringen gäller detta tillfälle."}</p>
    {plan && <div role="region" aria-label="Konsekvenser av tidsändringen">
      <h4>Kontrollera ändringen</h4>
      {!!plan.conflicts?.length && <div role="alert"><p>Ingen ändring kan sparas förrän alla konflikter är lösta.</p><ul>{plan.conflicts.map((conflict, index) => <li key={index}><strong>{conflict.resource_name}</strong> · {when(conflict.starts_at)}: {bookingError({message: conflict.reason})}</li>)}</ul></div>}
      {scope === "event" && <p>Aktivitet: {when(plan.event_starts_at!)}–{when(plan.event_ends_at!)} → {when(new Date(start).toISOString())}–{when(new Date(end).toISOString())}</p>}
      {(scope.endsWith("_forward") || scope.endsWith("_all")) && <p>{plan.events?.length ? `${plan.events.length} aktiviteter och ` : ""}{plan.bookings.length} resursbokningar berörs. Tiderna behålls i seriens lokala tidszon ({plan.timezone}), även över sommar- och vintertid.</p>}
      {!!plan.events?.length && <><h4>Aktiviteter</h4><ul>{plan.events.map(event => <li key={event.id}><strong>{event.title}</strong>: {when(event.old_starts_at)}–{when(event.old_ends_at)} → {when(event.starts_at)}–{when(event.ends_at)}</li>)}</ul></>}
      <h4>Resursbokningar</h4>
      <ul>{plan.bookings.map(row => <li key={row.id}><strong>{row.resource_name}</strong>: {when(row.old_starts_at)}–{when(row.old_ends_at)} → {when(row.starts_at)}–{when(row.ends_at)}. {statusLabels[row.status]}{row.old_status === "confirmed" && row.status === "pending" ? " – kräver nytt godkännande" : ""}.</li>)}</ul>
      <p>Om någon resurs hinner bli upptagen stoppas hela ändringen.</p>
    </div>}
    {error && <p role="alert" className="wt-error">{error}</p>}
    <div className="wt-actions">
      <button type="button" className="wt-button" disabled={busy} onClick={plan && !plan.conflicts?.length ? save : preview}>{busy ? "Kontrollerar…" : plan?.conflicts?.length ? "Förhandsvisa igen" : plan ? "Bekräfta tidsändringen" : "Förhandsvisa ändringen"}</button>
      <button type="button" className="wt-button secondary" disabled={busy} onClick={() => { setOpen(false); setPlan(null); setError(""); }}>Avbryt tidsändringen</button>
    </div>
  </section>;
}
