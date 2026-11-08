"use client";

import { useEffect, useRef, useState } from "react";
import { bookingError, categoryLabels, localInstant, resourcePath, type Organization, type Resource } from "../../lib/booking";
import { bookingAlternatives, type ResourceAvailabilityResult } from "../../lib/booking-alternatives";
import { useAccount } from "../account";

/** Mounted with an interval/resource key: changing the query discards old suggestions. */
export function BookingAlternatives({ org, resource, date, start, end, disabled, onChoose }: {
  org: Organization; resource: Resource; date: string; start: string; end: string;
  disabled: boolean; onChoose: (resource: Resource) => void;
}) {
  const { client } = useAccount();
  const [rows, setRows] = useState<ResourceAvailabilityResult[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [allTypes, setAllTypes] = useState(false);
  const generation = useRef(0);
  useEffect(() => () => { generation.current++; }, []);
  async function check() {
    if (!client || busy || disabled) return;
    if (!date || !start || !end) { setError("Välj datum, start och slut först."); return; }
    const from = localInstant(date, start);
    let to = localInstant(date, end);
    if (new Date(to) <= new Date(from)) to = new Date(new Date(to).getTime() + 86400e3).toISOString();
    if (Date.parse(from) <= Date.now()) { setError("Välj en kommande tid för att söka alternativ."); return; }
    const request = ++generation.current;
    setBusy(true); setError(""); setRows(null);
    try {
      const result = await client.schema("api").rpc("list_booking_availability", {
        target_organization_id: org.id, range_start: from, range_end: to,
      });
      if (request !== generation.current) return;
      if (result.error) setError(bookingError(result.error));
      else setRows((result.data ?? []) as ResourceAvailabilityResult[]);
    } catch { if (request === generation.current) setError("Alternativen kunde inte kontrolleras. Försök igen."); }
    finally { if (request === generation.current) setBusy(false); }
  }
  const available = rows ? bookingAlternatives(org.resources, rows, resource.id) : [];
  const shown = available.filter(item => allTypes || item.category === resource.category);
  return <section className="bk-alternatives" aria-label="Lediga resursalternativ">
    <div className="bk-panel-heading"><h3>Hitta en annan resurs</h3><button type="button" className="wt-button secondary small" disabled={busy || disabled} onClick={() => void check()}>{busy ? "Kontrollerar alternativ…" : rows ? "Kontrollera igen" : "Visa lediga alternativ"}</button></div>
    {error && <p role="alert" className="wt-error">{error}</p>}
    {rows && <>
      <p className="wt-small" role="status">{date} · {start}–{end}{end <= start ? " (nästa dag)" : ""} · din lokala tid. {allTypes ? "Alla resurstyper." : `Samma typ: ${categoryLabels[resource.category]}.`}</p>
      {shown.length === 0 ? <p>Inga andra lediga resurser {allTypes ? "finns för den här tiden" : "av samma typ finns för den här tiden"}. Ändra tiden eller kontrollera övriga resurstyper.</p> : <ul className="bk-alternative-list">{shown.map(item => <li key={item.id}><div><strong>{resourcePath(item, org.resources)}</strong><span>{[categoryLabels[item.category], item.location, item.capacity ? `${item.capacity} platser` : null, item.requires_approval && org.role !== "admin" ? "Kräver godkännande" : "Bokas direkt"].filter(Boolean).join(" · ")}</span></div><button type="button" className="wt-button secondary small" disabled={disabled} onClick={() => onChoose(item)} aria-label={`Välj ${resourcePath(item, org.resources)} istället`}>Välj istället</button></li>)}</ul>}
      <button type="button" className="wt-link-button" onClick={() => setAllTypes(!allTypes)}>{allTypes ? "Visa bara samma resurstyp" : "Visa alla resurstyper"}</button>
      <p className="wt-small">Kontrollerat för den valda tiden, inklusive överordnade och underordnade delar samt bokningsbara tider. Inget reserveras här. Tillgängligheten kontrolleras igen när du bokar.</p>
    </>}
  </section>;
}
