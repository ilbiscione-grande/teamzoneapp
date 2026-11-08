"use client";

import { useState } from "react";
import { bookingError, categoryLabels, statusLabels, type Booking, type Resource } from "../../lib/booking";
import { bookingCommand } from "../../lib/booking-command";
import { useAccount } from "../account";

type Scope = "booking" | "series_forward" | "series_all" | "event_forward" | "event_all";
type Reserved = { id: string; resource_id: string; resource_name: string; starts_at: string; ends_at: string; status: Booking["status"] };
type Addition = Omit<Reserved, "id">;
type Context = { anchor_booking_id: string; starts_at: string; ends_at: string; existing: Reserved[]; add: Addition[]; remove: Reserved[]; keep: Reserved[];
  unchanged_resources: { resource_name: string; reason: string }[] };
type Plan = { contexts: Context[]; change_count: number; unchanged_contexts: { starts_at: string; title?: string }[];
  conflicts: { resource_name: string; starts_at: string; reason: string }[] };
const when = (iso: string) => new Date(iso).toLocaleString("sv-SE", { dateStyle: "short", timeStyle: "short" });

export function BookingResourcesEditor({ booking, resources, onChanged }: { booking: Booking; resources: Resource[]; onChanged: () => void }) {
  const { client } = useAccount();
  const [open, setOpen] = useState(false);
  const [base, setBase] = useState<Context | null>(null);
  const [scope, setScope] = useState<Scope>("booking");
  const [add, setAdd] = useState<string[]>([]);
  const [remove, setRemove] = useState<string[]>([]);
  const [plan, setPlan] = useState<Plan | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  async function start() {
    if (!client) return;
    setOpen(true); setBusy(true); setError("");
    try {
      const result = await client.schema("api").rpc("preview_booking_resources", { target_booking_id: booking.id, change_scope: "booking", add_resource_ids: [], remove_resource_ids: [] });
      if (result.error) setError(bookingError(result.error));
      else setBase((result.data as Plan).contexts[0]);
    } catch { setError("Resurserna kunde inte hämtas. Försök igen."); }
    finally { setBusy(false); }
  }
  function toggle(id: string, adding: boolean) {
    const current = adding ? add : remove;
    (adding ? setAdd : setRemove)(current.includes(id) ? current.filter(x => x !== id) : [...current, id]);
    setPlan(null); setError("");
  }
  const params = () => ({ target_booking_id: booking.id, change_scope: scope, add_resource_ids: add, remove_resource_ids: remove });
  async function preview() {
    if (!client) return;
    setBusy(true); setPlan(null); setError("");
    try {
      const result = await client.schema("api").rpc("preview_booking_resources", params());
      if (result.error) setError(bookingError(result.error)); else setPlan(result.data as Plan);
    } catch { setError("Förhandsvisningen kunde inte hämtas. Försök igen."); }
    finally { setBusy(false); }
  }
  async function save() {
    if (!client || !plan || plan.conflicts.length || !plan.change_count) return;
    setBusy(true); setError("");
    try {
      const result = await bookingCommand(client, "update_booking_resources", { ...params(), expected_plan: plan });
      if (result.error) {
        setError(bookingError(result.error));
        if (["stale_revision", "resource_set_conflicts"].includes(result.error.message)) setPlan(null);
      } else onChanged();
    } catch { setError("Svaret kunde inte hämtas. Försök igen med samma ändring."); }
    finally { setBusy(false); }
  }
  if (!open) return <button type="button" className="wt-button secondary" onClick={start}>Hantera resurser</button>;
  const available = resources.filter(r => r.active && !base?.existing.some(b => b.resource_id === r.id));
  const ready = !!plan && !plan.conflicts.length && plan.change_count > 0;
  return <section className="wt-form" aria-label="Lägg till eller ta bort resurser">
    <h3>Lägg till och ta bort resurser</h3>
    {(booking.series_id || booking.resource_event_series) && <label>Omfattning<select aria-label="Resursändringens omfattning" value={scope} disabled={busy} onChange={e => { setScope(e.target.value as Scope); setPlan(null); setError(""); }}>
      <option value="booking">Bara detta tillfälle</option>
      {booking.series_id && <><option value="series_forward">Detta och följande i bokningsserien</option><option value="series_all">Hela den kommande bokningsserien</option></>}
      {booking.resource_event_series && <><option value="event_forward">Detta och följande i aktivitetsserien</option><option value="event_all">Hela den kommande aktivitetsserien</option></>}
    </select></label>}
    <p>{scope === "booking" ? "Ändrar bara resurserna i denna bokning. Övriga tillfällen lämnas kvar."
      : `Ändrar resurser där ${booking.resource_name} fortfarande är bokad i ${scope.endsWith("_all") ? "hela den kommande serien, även före det valda tillfället" : "detta och följande tillfällen"}. Andra manuella resursval lämnas kvar. Tidigare avbokade eller nekade resurser bokas inte på nytt automatiskt.`}</p>
    <p>Nya resurser får samma bokningstid som {booking.resource_name}. Befintliga resursers egna tider och aktivitetskopplingar behålls. Pågående och tidigare resursbokningar kan inte tas bort här.</p>
    {base && <>
      <fieldset disabled={busy}><legend>Ta bort från bokningen</legend>
        {base.existing.map(b => <label key={b.id}><input type="checkbox" checked={remove.includes(b.resource_id)} disabled={Date.parse(b.starts_at) <= Date.now()} onChange={() => toggle(b.resource_id, false)} />{b.resource_name} · {when(b.starts_at)}–{when(b.ends_at)}</label>)}
      </fieldset>
      <fieldset disabled={busy}><legend>Lägg till i bokningen</legend>
        {available.map(r => <label key={r.id}><input type="checkbox" checked={add.includes(r.id)} onChange={() => toggle(r.id, true)} />{r.name} · {categoryLabels[r.category]}{r.requires_approval ? " · kräver godkännande" : ""}</label>)}
        {!available.length && <p>Det finns inga fler aktiva resurser att lägga till.</p>}
      </fieldset>
    </>}
    {plan && <div role="region" aria-label="Konsekvenser av resursändringen">
      <h4>Kontrollera resursändringen</h4>
      <p>{plan.contexts.length} tillfällen kontrollerade. {plan.change_count} tillägg och borttagningar.</p>
      {!plan.change_count && <p>Inga resurser behöver ändras med dina val.</p>}
      {plan.contexts.map((ctx, index) => <div key={ctx.anchor_booking_id}>
        <h4>Tillfälle {index + 1} · {when(ctx.starts_at)}</h4>
        {!!ctx.add.length && <><strong>Läggs till</strong><ul>{ctx.add.map(r => <li key={r.resource_id}>{r.resource_name}: {when(r.starts_at)}–{when(r.ends_at)}. {statusLabels[r.status]}{r.status === "pending" ? " – kräver godkännande" : ""}.</li>)}</ul></>}
        {!!ctx.remove.length && <><strong>Tas bort</strong><ul>{ctx.remove.map(r => <li key={r.id}>{r.resource_name}: {when(r.starts_at)}–{when(r.ends_at)}. Resursbokningen avbokas och finns kvar i historiken.</li>)}</ul></>}
        {!!ctx.keep.length && <><strong>Behålls</strong><ul>{ctx.keep.map(r => <li key={r.id}>{r.resource_name}: {when(r.starts_at)}–{when(r.ends_at)}. {statusLabels[r.status]}.</li>)}</ul></>}
        {!ctx.keep.length && !ctx.add.length && <p>Efter ändringen har tillfället inga aktiva resursbokningar.{booking.event_id ? " Själva aktiviteten finns kvar." : ""}</p>}
        {!!ctx.unchanged_resources.length && <ul>{ctx.unchanged_resources.map((r, i) => <li key={i}>{r.resource_name}: {r.reason === "previously_cancelled" ? "tidigare avbokad eller nekad – lämnas kvar utan ny bokning" : "redan bokad – behålls utan dubbel bokning"}.</li>)}</ul>}
      </div>)}
      {!!plan.unchanged_contexts.length && <><h4>Andra resursval lämnas kvar ({plan.unchanged_contexts.length})</h4><ul>{plan.unchanged_contexts.map((row, i) => <li key={i}>{when(row.starts_at)}{row.title ? ` · ${row.title}` : ""}: har inte den valda ursprungsresursen bokad.</li>)}</ul></>}
      {!!plan.conflicts.length && <div role="alert"><p>Ingen ändring kan sparas förrän alla konflikter är lösta. Befintliga bokningar är kvar.</p><ul>{plan.conflicts.map((c, i) => <li key={i}>{when(c.starts_at)} · {c.resource_name}: {bookingError({message:c.reason})}</li>)}</ul></div>}
      <p>Allt sparas tillsammans. Om en resurs hinner bli upptagen stoppas hela ändringen.</p>
    </div>}
    {error && <p role="alert" className="wt-error">{error}</p>}
    <div className="wt-actions">
      <button type="button" className="wt-button" disabled={busy || !base || (!add.length && !remove.length)} onClick={ready ? save : preview}>{busy ? "Kontrollerar…" : ready ? "Bekräfta resursändringen" : plan ? "Förhandsvisa resursändringen igen" : "Förhandsvisa resursändringen"}</button>
      <button type="button" className="wt-button secondary" disabled={busy} onClick={() => { setOpen(false); setBase(null); setPlan(null); setAdd([]); setRemove([]); setScope("booking"); setError(""); }}>Avbryt resursändringen</button>
      {!base && error && <button type="button" className="wt-button secondary" disabled={busy} onClick={start}>Hämta resurser igen</button>}
    </div>
  </section>;
}
