"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { bookingError, invitationToken, kindLabels, type OrgKind, type OrganizationSummary } from "../../lib/booking";
import { useAccount } from "../account";

/** Your organisations, a new one, or an invitation to join. */
export function BookingHome() {
  const { client } = useAccount();
  const router = useRouter();
  const params = useSearchParams();
  const [orgs, setOrgs] = useState<OrganizationSummary[] | null>(null);
  const [error, setError] = useState("");
  const [creating, setCreating] = useState(false);
  const [name, setName] = useState("");
  const [kind, setKind] = useState<OrgKind>("club");
  const [sport, setSport] = useState("");
  const [invite, setInvite] = useState("");
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    if (!client) return;
    const { data, error: loadError } = await client.schema("api").rpc("list_booking_organizations");
    if (loadError) { setError(bookingError(loadError)); return; }
    setOrgs(data as OrganizationSummary[]);
  }, [client]);

  useEffect(() => { void load(); }, [load]);

  const accept = useCallback(async (value: string) => {
    if (!client) return;
    const token = invitationToken(value);
    if (!token) { setError("Länken ser inte ut som en inbjudan."); return; }
    setBusy(true);
    const { data, error: acceptError } = await client.schema("api").rpc("accept_booking_invitation", { invite_token: token });
    setBusy(false);
    if (acceptError) { setError(bookingError(acceptError)); return; }
    router.push(`/bokningar/${data}`);
  }, [client, router]);

  // Arriving from an invitation link: join at once.
  const linked = params.get("inbjudan");
  useEffect(() => { if (linked && client) void accept(linked); }, [linked, client, accept]);

  const create = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!client || !name.trim()) return;
    setBusy(true);
    const { data, error: createError } = await client.schema("api").rpc("create_booking_organization", { org_name: name, org_kind: kind, org_sport: sport || null });
    setBusy(false);
    if (createError) { setError(bookingError(createError)); return; }
    router.push(`/bokningar/${data}`);
  };

  return (
    <div className="bk-home">
      {error && <p role="alert" className="wt-error">{error}</p>}
      <section className="wt-panel">
        <h2>Dina organisationer</h2>
        {orgs === null ? <p className="wt-status">Laddar…</p> : orgs.length === 0 ? (
          <p>Du är inte med i någon organisation än. Skapa en för din klubb eller förening, eller gå med via en inbjudan.</p>
        ) : (
          <ul className="bk-orgs">
            {orgs.map(org => (
              <li key={org.id}>
                <Link href={`/bokningar/${org.id}`}>
                  <strong>{org.name}</strong>
                  <span>{[kindLabels[org.kind], org.sport, org.teamzone_club_name ? `Kopplad till ${org.teamzone_club_name} i TeamZone` : null, org.role === "admin" ? "Administratör" : "Bokare"].filter(Boolean).join(" · ")}</span>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </section>
      <section className="wt-panel">
        <h2>Ny organisation</h2>
        {creating ? (
          <form className="wt-form" onSubmit={create}>
            <label>Namn<input value={name} onChange={event => setName(event.target.value)} maxLength={120} required placeholder="T.ex. Demoklubben IF" /></label>
            <label>Typ
              <select value={kind} onChange={event => setKind(event.target.value as OrgKind)}>
                {Object.entries(kindLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
              </select>
            </label>
            <label>Sport eller verksamhet (frivilligt)<input value={sport} onChange={event => setSport(event.target.value)} maxLength={60} placeholder="T.ex. Fotboll" /></label>
            <div className="wt-actions">
              <button type="submit" className="wt-button" disabled={busy || !name.trim()}>Skapa</button>
              <button type="button" className="wt-button secondary" onClick={() => setCreating(false)}>Avbryt</button>
            </div>
          </form>
        ) : (
          <>
            <p>Lägg upp klubbens eller föreningens resurser: planer, lokaler, fordon eller utrustning. Du blir administratör och bjuder in de som ska boka.</p>
            <button type="button" className="wt-button" onClick={() => setCreating(true)}>Skapa organisation</button>
          </>
        )}
      </section>
      <section className="wt-panel">
        <h2>Har du fått en inbjudan?</h2>
        <form className="wt-form" onSubmit={event => { event.preventDefault(); void accept(invite); }}>
          <label>Inbjudningslänk<input value={invite} onChange={event => setInvite(event.target.value)} placeholder="Klistra in länken" /></label>
          <button type="submit" className="wt-button secondary" disabled={busy || !invite.trim()}>Gå med</button>
        </form>
        <p className="wt-small">Är din klubb kopplad till TeamZone och du är ledare där, syns den ovan utan inbjudan.</p>
      </section>
    </div>
  );
}
