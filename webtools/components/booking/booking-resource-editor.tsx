"use client";

import { useState } from "react";
import { bookingError, categoryLabels, statusLabels, type Booking, type Resource } from "../../lib/booking";
import { bookingCommand } from "../../lib/booking-command";
import { useAccount } from "../account";

type SinglePlan = {
  old_resource_name: string; new_resource_name: string; starts_at: string; ends_at: string;
  old_status: Booking["status"]; status: Booking["status"]; event_id: string | null;
  series_id: string | null; group_id: string | null; conflicts: string[];
};
type Scope = "booking" | "series_forward" | "series_all" | "event_forward" | "event_all";
type SeriesPlan = {
  bookings: SinglePlan[];
  unchanged: { id?: string; event_id?: string; title?: string; resource_name?: string; starts_at: string; ends_at: string; reason: string }[];
  conflicts: { booking_id: string; resource_name: string; starts_at: string; reason: string }[];
};
type Plan = SinglePlan | SeriesPlan;
const when = (iso: string) => new Date(iso).toLocaleString("sv-SE", { dateStyle: "short", timeStyle: "short" });

export function BookingResourceEditor({ booking, resources, onChanged }: {
  booking: Booking; resources: Resource[]; onChanged: () => void;
}) {
  const { client } = useAccount();
  const [open, setOpen] = useState(false);
  const [resource, setResource] = useState("");
  const [scope, setScope] = useState<Scope>("booking");
  const [plan, setPlan] = useState<Plan | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const alternatives = resources.filter(r => r.active && r.id !== booking.resource_id);
  async function preview() {
    if (!client || !resource) return;
    setBusy(true); setError(""); setPlan(null);
    try {
      const params = { target_booking_id: booking.id, new_resource_id: resource };
      const result = scope === "booking"
        ? await client.schema("api").rpc("preview_booking_resource", params)
        : await client.schema("api").rpc("preview_booking_resource_series", { ...params, change_scope: scope });
      if (result.error) setError(bookingError(result.error));
      else setPlan(result.data as Plan);
    } catch { setError("Förhandsvisningen kunde inte hämtas. Försök igen."); }
    finally { setBusy(false); }
  }
  async function save() {
    if (!client || !plan || plan.conflicts.length) return;
    setBusy(true); setError("");
    try {
      const result = await bookingCommand(client, "change_booking_resource", {
        target_booking_id: booking.id, new_resource_id: resource, change_scope: scope, expected_plan: plan,
      });
      if (result.error) {
        setError(bookingError(result.error));
        if (["stale_revision", "resource_change_conflicts"].includes(result.error.message)) setPlan(null);
      } else onChanged();
    } catch { setError("Svaret kunde inte hämtas. Försök igen med samma ändring."); }
    finally { setBusy(false); }
  }
  if (!open) return <button type="button" className="wt-button secondary" onClick={() => setOpen(true)}>Byt resurs</button>;
  return <section className="wt-form" aria-label="Byt bokningens resurs">
    <h3>Byt resurs</h3>
    {(booking.series_id || booking.resource_event_series) && <label>Omfattning<select aria-label="Resursbytets omfattning" value={scope} disabled={busy} onChange={e => { setScope(e.target.value as Scope); setPlan(null); setError(""); }}>
      <option value="booking">Bara detta tillfälle</option>
      {booking.series_id && <><option value="series_forward">Detta och följande i bokningsserien</option><option value="series_all">Hela den kommande bokningsserien</option></>}
      {booking.resource_event_series && <><option value="event_forward">Detta och följande i aktivitetsserien</option><option value="event_all">Hela den kommande aktivitetsserien</option></>}
    </select></label>}
    <p>{scope === "booking" ? "Bokningens tider behålls. Övriga tillfällen i serien och andra resurser i bokningsgruppen ändras inte."
      : `Byter ${booking.resource_name} där resursen fortfarande är bokad i ${scope.endsWith("_all") ? "hela den kommande serien, även tillfällen före det valda" : "detta och följande tillfällen i seriens ordning"}. Tider, övriga resurser och tidigare manuella resursval behålls. Pågående, tidigare och avbokade tillfällen lämnas kvar.`}</p>
    {booking.event_id && <p>Aktivitetskopplingen och tidsmarginalerna mot aktiviteten behålls.</p>}
    <label>Ny resurs<select aria-label="Ny resurs" value={resource} disabled={busy} onChange={e => { setResource(e.target.value); setPlan(null); setError(""); }}>
      <option value="">Välj resurs</option>
      {alternatives.map(r => <option key={r.id} value={r.id}>{r.name} · {categoryLabels[r.category]}{r.requires_approval ? " · kräver godkännande" : ""}</option>)}
    </select></label>
    {!alternatives.length && <p>Det finns inga andra aktiva resurser i organisationen.</p>}
    {plan && <div role="region" aria-label="Konsekvenser av resursbytet">
      <h4>Kontrollera resursbytet</h4>
      {"bookings" in plan && <p>{plan.bookings.length} resursbokningar byter resurs. Alla tider och aktivitetskopplingar behålls. Aktiviteter utan ursprungsresursen får ingen ny bokning.</p>}
      <ul>{("bookings" in plan ? plan.bookings : [plan]).map((row, index) => <li key={index}>
        <strong>{row.old_resource_name}</strong> → <strong>{row.new_resource_name}</strong><br />
        {when(row.starts_at)}–{when(row.ends_at)}. Tiderna är oförändrade.<br />
        Efter bytet: {statusLabels[row.status]}.{row.status === "pending" ? " Den nya resursen kräver godkännande innan bokningen är bekräftad." : ""}
      </li>)}</ul>
      {"unchanged" in plan && !!plan.unchanged.length && <><h4>Lämnas oförändrade ({plan.unchanged.length})</h4><ul>{plan.unchanged.map((row, index) => <li key={index}>{when(row.starts_at)}: {row.reason === "different_resource" ? `använder redan ${row.resource_name}` : `${row.title ?? "Aktiviteten"} har ingen kommande aktiv bokning av ursprungsresursen`}.</li>)}</ul></>}
      {!!plan.conflicts.length && <div role="alert"><p>Inget resursbyte kan sparas. Alla befintliga bokningar är kvar.</p><ul>{plan.conflicts.map((conflict, index) => <li key={index}>{typeof conflict === "string" ? bookingError({message: conflict}) : `${when(conflict.starts_at)} · ${conflict.resource_name}: ${bookingError({message: conflict.reason})}`}</li>)}</ul></div>}
      <p>De gamla resurserna släpps först när hela bytet kan sparas. Om den nya resursen hinner bli upptagen vid något tillfälle stoppas hela ändringen.</p>
    </div>}
    {error && <p role="alert" className="wt-error">{error}</p>}
    <div className="wt-actions">
      <button type="button" className="wt-button" disabled={busy || !resource} onClick={plan && !plan.conflicts.length ? save : preview}>{busy ? "Kontrollerar…" : plan?.conflicts.length ? "Förhandsvisa resursbytet igen" : plan ? "Bekräfta resursbytet" : "Förhandsvisa resursbytet"}</button>
      <button type="button" className="wt-button secondary" disabled={busy} onClick={() => { setOpen(false); setPlan(null); setError(""); }}>Avbryt resursbytet</button>
    </div>
  </section>;
}
