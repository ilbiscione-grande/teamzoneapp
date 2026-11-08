"use client";

import { useRef, useState } from "react";
import { bookingError, categoryLabels, statusLabels, type Booking, type Resource } from "../../lib/booking";
import { bookingCommand } from "../../lib/booking-command";
import { useAccount } from "../account";
import { bookingChangeScopes, bookingConflictHint, type BookingChangeScope } from "../../lib/booking-change";

type Scope = BookingChangeScope;
type Reserved = { id: string; resource_id: string; resource_name: string; starts_at: string; ends_at: string; status: Booking["status"] };
type Addition = Omit<Reserved, "id">;
type Context = { anchor_booking_id: string; starts_at: string; ends_at: string; existing: Reserved[]; add: Addition[]; remove: Reserved[]; keep: TimeRow[];
  unchanged_resources: { resource_name: string; reason: string }[] };
type TimeRow = Reserved & {old_starts_at: string; old_ends_at: string};
type Plan = { future_plan?: {state:string;configuration:{resources:{resource_name:string}[]};slots:{local_start:string}[]}|null; timing: { timezone: string; events: {id:string;title:string;old_starts_at:string;old_ends_at:string;starts_at:string;ends_at:string}[]; bookings:TimeRow[] };
  final_bookings: (TimeRow & {key?:string})[]; selection: {unchanged_contexts: {starts_at:string;title?:string}[]}; contexts: Context[]; change_count: number; unchanged_contexts: { starts_at: string; title?: string }[];
  conflicts: { resource_name: string; starts_at: string; reason: string }[] };
function inputTime(iso: string) { const d=new Date(iso);return new Date(d.getTime()-d.getTimezoneOffset()*60000).toISOString().slice(0,16); }
const when = (iso: string) => new Date(iso).toLocaleString("sv-SE", { dateStyle: "short", timeStyle: "short" });

export function BookingEditor({ booking, resources, onChanged, onOpenChange }: { booking: Booking; resources: Resource[]; onChanged: () => void; onOpenChange?: (open: boolean) => void }) {
  const { client } = useAccount();
  const [startTime,setStartTime]=useState(inputTime(booking.event_starts_at ?? booking.starts_at));
  const [endTime,setEndTime]=useState(inputTime(booking.event_ends_at ?? booking.ends_at));
  const [open, setOpen] = useState(false);
  const [base, setBase] = useState<Context | null>(null);
  const [scope, setScope] = useState<Scope>("booking");
  const [add, setAdd] = useState<string[]>([]);
  const [remove, setRemove] = useState<string[]>([]);
  const [plan, setPlan] = useState<Plan | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const timeInput = useRef<HTMLInputElement>(null);
  const resourceOptions = useRef<HTMLDetailsElement>(null);
  async function start() {
    if (!client || busy) return;
    setOpen(true); onOpenChange?.(true); setBusy(true); setError("");
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
  const params = () => ({ target_booking_id: booking.id, change_scope: scope, add_resource_ids: add, remove_resource_ids: remove, new_starts_at: new Date(startTime).toISOString(), new_ends_at: new Date(endTime).toISOString() });
  async function preview() {
    if (!client || busy) return;
    if (!startTime || !endTime || !Number.isFinite(Date.parse(startTime)) || !Number.isFinite(Date.parse(endTime)) || Date.parse(endTime)<=Date.parse(startTime)) { setError("Ange start och slut. Slutet måste vara efter starten.");return; }
    if(inputTime(new Date(startTime).toISOString())!==startTime || inputTime(new Date(endTime).toISOString())!==endTime) {setError("Klocktiden finns inte vid övergången till sommartid. Välj en annan tid.");return;}
    setBusy(true); setPlan(null); setError("");
    try {
      const result = await client.schema("api").rpc("preview_booking_change", params());
      if (result.error) setError(bookingError(result.error)); else setPlan(result.data as Plan);
    } catch { setError("Förhandsvisningen kunde inte hämtas. Försök igen."); }
    finally { setBusy(false); }
  }
  async function save() {
    if (!client || busy || !plan || plan.conflicts.length || !plan.change_count) return;
    setBusy(true); setError("");
    try {
      const result = await bookingCommand(client, "update_booking", { ...params(), expected_plan: plan });
      if (result.error) {
        setError(bookingError(result.error));
        if (["stale_revision", "booking_change_conflicts"].includes(result.error.message)) setPlan(null);
      } else onChanged();
    } catch { setError("Svaret kunde inte hämtas. Försök igen med samma ändring."); }
    finally { setBusy(false); }
  }
  if (!open) return <button type="button" className="wt-button" onClick={start} disabled={!!booking.event_id && !booking.can_move_event}>Ändra tid och resurser</button>;
  const available = resources.filter(r => r.active && !base?.existing.some(b => b.resource_id === r.id));
  const ready = !!plan && !plan.conflicts.length && plan.change_count > 0;
  return <section className="wt-form" aria-label="Ändra tid och resurser">
    <h3>Ändra tid och resurser</h3>
    {(booking.series_id || booking.resource_event_series) && <fieldset disabled={busy} className="bk-change-scope"><legend>Vilka tillfällen vill du ändra?</legend>{bookingChangeScopes(booking).map(option => <label className="bk-scope-option" key={option.value}><input type="radio" name={`booking-scope-${booking.id}`} checked={scope === option.value} onChange={() => { setScope(option.value); setPlan(null); setError(""); }} /><span><strong>{option.label}</strong><small>{option.hint}</small></span></label>)}</fieldset>}
    <p>{scope === "booking" ? "Ändrar tiden och resurserna för detta tillfälle. Övriga tillfällen lämnas kvar."
      : `Tiden ändras för alla kommande tillfällen i vald omfattning. Resursval ändras där ${booking.resource_name} fortfarande är bokad i ${scope.endsWith("_all") ? "hela den kommande serien, även före det valda tillfället" : "detta och följande tillfällen"}. Andra manuella resursval behålls och följer med tidsändringen. Tidigare avbokade eller nekade resurser bokas inte på nytt automatiskt.`}</p>
    <p>{booking.event_id ? "Ange aktivitetens nya tid. Alla dess resursbokningar följer med och behåller sina individuella tidsmarginaler." : "Ange den valda resursens nya tid. Övriga resurser följer med och behåller sina individuella tidsmarginaler."} Nya resurser får samma nya bokningstid som {booking.resource_name}.</p>
    <label>Ny start<input ref={timeInput} aria-label="Ny start" type="datetime-local" value={startTime} disabled={busy} onChange={e=>{setStartTime(e.target.value);setPlan(null);}} /></label>
    <label>Nytt slut<input aria-label="Nytt slut" type="datetime-local" value={endTime} disabled={busy} onChange={e=>{setEndTime(e.target.value);setPlan(null);}} /></label>
    <p className="wt-small">Tiderna visas i {Intl.DateTimeFormat().resolvedOptions().timeZone}. Serien följer sin lokala tidszon över sommar- och vintertid.</p>
    {base && <details className="bk-resource-details" ref={resourceOptions}><summary>Ändra resursval{add.length + remove.length ? ` · ${add.length} tillägg, ${remove.length} borttagningar` : " (frivilligt)"}</summary>
      <p className="wt-small">Bokade resurser följer med till den nya tiden. Öppna bara om du också vill lägga till eller ta bort resurser.</p>
      <fieldset disabled={busy}><legend>Ta bort från bokningen</legend>
        {base.existing.map(b => <label key={b.id}><input type="checkbox" checked={remove.includes(b.resource_id)} disabled={Date.parse(b.starts_at) <= Date.now()} onChange={() => toggle(b.resource_id, false)} />{b.resource_name} · {when(b.starts_at)}–{when(b.ends_at)}</label>)}
      </fieldset>
      <fieldset disabled={busy}><legend>Lägg till i bokningen</legend>
        {available.map(r => <label key={r.id}><input type="checkbox" checked={add.includes(r.id)} onChange={() => toggle(r.id, true)} />{r.name} · {categoryLabels[r.category]}{r.requires_approval ? " · kräver godkännande" : ""}</label>)}
        {!available.length && <p>Det finns inga fler aktiva resurser att lägga till.</p>}
      </fieldset>
    </details>}
    {plan && <div role="region" aria-label="Konsekvenser av bokningsändringen">
      <h4>Kontrollera hela ändringen</h4>
      <p>Alla tider och resursval nedan sparas tillsammans.</p>
      <div className="wt-note bk-change-summary"><p><strong>{plan.change_count} ändringar</strong> · {plan.timing.events.length} aktiviteter · {plan.final_bookings.length} resursbokningar efter ändringen</p>
        {!!plan.contexts.flatMap(ctx => ctx.add).length && <p>Läggs till: {[...new Set(plan.contexts.flatMap(ctx => ctx.add.map(r => r.resource_name)))].join(", ")}</p>}
        {!!plan.contexts.flatMap(ctx => ctx.remove).length && <p>Tas bort: {[...new Set(plan.contexts.flatMap(ctx => ctx.remove.map(r => r.resource_name)))].join(", ")}</p>}
        {!plan.timing.events.length && <p>Ingen aktivitet flyttas av den här ändringen.</p>}
      </div>
      {!!plan.conflicts.length && <div className="bk-change-conflicts" role="alert"><h4>Lös {plan.conflicts.length === 1 ? "konflikten" : `${plan.conflicts.length} konflikter`} före bekräftelse</h4><p>Ingen ändring har sparats. Dina befintliga bokningar ligger kvar.</p><ul>{plan.conflicts.map((c, i) => <li key={i}><strong>{when(c.starts_at)} · {c.resource_name}</strong><p>{bookingError({message:c.reason})}</p><p className="wt-small">{bookingConflictHint(c.reason)}</p></li>)}</ul><div className="wt-actions"><button type="button" className="wt-button secondary small" onClick={() => timeInput.current?.focus()}>Ändra tid</button><button type="button" className="wt-button secondary small" onClick={() => { if(resourceOptions.current) { resourceOptions.current.open = true; resourceOptions.current.querySelector("input")?.focus(); } }}>Ändra resursval</button></div></div>}
      {plan.future_plan && <div><h4>Seriegrunden följer också ändringen</h4><p>{plan.future_plan.slots.length} ännu inte skapade tillfällen får samma tidsändring. Framtida resurser: {plan.future_plan.configuration.resources.map(r=>r.resource_name).join(", ") || "inga – automatiken pausas för en fristående bokningsserie"}. {plan.future_plan.state==="paused"?"Automatiken är pausad.":"Lediga tillfällen inom 90 dagar skapas när ändringen sparas."}</p></div>}
      <details className="bk-resource-details" open={plan.contexts.length === 1}><summary>Visa alla tider och resursändringar</summary>
      {!!plan.timing.events.length && <><h4>Aktiviteter</h4><ul>{plan.timing.events.map(e=><li key={e.id}>{e.title}: {when(e.old_starts_at)}–{when(e.old_ends_at)} → {when(e.starts_at)}–{when(e.ends_at)}</li>)}</ul></>}
      <h4>Kvarvarande resursers tider</h4><ul>{plan.final_bookings.filter(r=>r.id).map(r=><li key={r.id}><strong>{r.resource_name}</strong>: {when(r.old_starts_at)}–{when(r.old_ends_at)} → {when(r.starts_at)}–{when(r.ends_at)}. {statusLabels[r.status]}.</li>)}</ul>
      {!plan.change_count && <p>Ingen tid eller resurs behöver ändras med dina val.</p>}
      {plan.contexts.map((ctx, index) => <div key={ctx.anchor_booking_id}>
        <h4>Tillfälle {index + 1} · {when(ctx.starts_at)}</h4>
        {!!ctx.add.length && <><strong>Läggs till</strong><ul>{ctx.add.map(r => <li key={r.resource_id}>{r.resource_name}: {when(r.starts_at)}–{when(r.ends_at)}. {statusLabels[r.status]}{r.status === "pending" ? " – kräver godkännande" : ""}.</li>)}</ul></>}
        {!!ctx.remove.length && <><strong>Tas bort</strong><ul>{ctx.remove.map(r => <li key={r.id}>{r.resource_name}: {when(r.starts_at)}–{when(r.ends_at)}. Resursbokningen avbokas och finns kvar i historiken.</li>)}</ul></>}
        {!!ctx.keep.length && <><strong>Behålls</strong><ul>{ctx.keep.map(r => <li key={r.id}>{r.resource_name}: {when(r.starts_at)}–{when(r.ends_at)}. {statusLabels[r.status]}.</li>)}</ul></>}
        {!ctx.keep.length && !ctx.add.length && <p>Efter ändringen har tillfället inga aktiva resursbokningar.{booking.event_id ? " Själva aktiviteten finns kvar." : ""}</p>}
        {!!ctx.unchanged_resources.length && <ul>{ctx.unchanged_resources.map((r, i) => <li key={i}>{r.resource_name}: {r.reason === "previously_cancelled" ? "tidigare avbokad eller nekad – lämnas kvar utan ny bokning" : "redan bokad – behålls utan dubbel bokning"}.</li>)}</ul>}
      </div>)}
      {!!plan.selection.unchanged_contexts.length && <><h4>Andra resursval behålls ({plan.selection.unchanged_contexts.length})</h4><ul>{plan.selection.unchanged_contexts.map((row, i) => <li key={i}>{when(row.starts_at)}{row.title ? ` · ${row.title}` : ""}: resursvalet behålls. Se tidsändringen ovan.</li>)}</ul></>}
      </details>
      <p>Allt sparas tillsammans. Om en resurs hinner bli upptagen stoppas hela ändringen.</p>
    </div>}
    {error && <p role="alert" className="wt-error">{error}</p>}
    <div className="wt-actions">
      <button type="button" className="wt-button" disabled={busy || !base} onClick={ready ? save : preview}>{busy ? "Kontrollerar…" : ready ? "Bekräfta tid och resurser" : plan ? "Förhandsvisa ändringen igen" : "Förhandsvisa ändringen"}</button>
      <button type="button" className="wt-button secondary" disabled={busy} onClick={() => { setOpen(false); onOpenChange?.(false); setBase(null); setPlan(null); setAdd([]); setRemove([]); setScope("booking"); setStartTime(inputTime(booking.event_starts_at ?? booking.starts_at)); setEndTime(inputTime(booking.event_ends_at ?? booking.ends_at)); setError(""); }}>Avbryt ändringen</button>
      {!base && error && <button type="button" className="wt-button secondary" disabled={busy} onClick={start}>Hämta resurser igen</button>}
    </div>
  </section>;
}
