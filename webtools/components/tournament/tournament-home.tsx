"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { dateSpan, roleLabels, staffInvitationToken, tournamentError, tournamentStatusLabels, type TournamentSummary } from "../../lib/tournament";
import { useAccount } from "../account";

/** Tournaments you organise or have registered in, a new one, or a staff invitation. */
export function TournamentHome() {
  const { client } = useAccount();
  const router = useRouter();
  const params = useSearchParams();
  const [tournaments, setTournaments] = useState<TournamentSummary[] | null>(null);
  const [error, setError] = useState("");
  const [creating, setCreating] = useState(false);
  const [form, setForm] = useState({ name: "", sport: "", location: "", starts_on: "", ends_on: "" });
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    if (!client) return;
    const { data, error: loadError } = await client.schema("api").rpc("list_my_tournaments");
    if (loadError) { setError(tournamentError(loadError)); return; }
    setTournaments(data as TournamentSummary[]);
  }, [client]);

  useEffect(() => { void load(); }, [load]);

  // Arriving from a staff invitation: join at once.
  const linked = params.get("inbjudan");
  useEffect(() => {
    if (!linked || !client) return;
    const token = staffInvitationToken(linked);
    if (!token) return;
    void client.schema("api").rpc("accept_tournament_staff_invitation", { invite_token: token }).then(({ data, error: acceptError }) => {
      if (acceptError) { setError(tournamentError(acceptError)); return; }
      router.push(`/turneringar/${data}`);
    });
  }, [linked, client, router]);

  const create = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!client) return;
    setBusy(true);
    const { data, error: createError } = await client.schema("api").rpc("create_tournament", {
      tournament_name: form.name, tournament_sport: form.sport || null, tournament_location: form.location || null,
      tournament_starts_on: form.starts_on, tournament_ends_on: form.ends_on || form.starts_on,
    });
    setBusy(false);
    if (createError) { setError(tournamentError(createError)); return; }
    router.push(`/turneringar/${data}`);
  };

  return (
    <div className="bk-home">
      {error && <p role="alert" className="wt-error">{error}</p>}
      <section className="wt-panel">
        <h2>Dina turneringar</h2>
        {tournaments === null ? <p className="wt-status">Laddar…</p> : tournaments.length === 0 ? (
          <p>Du har inga turneringar än. Skapa en, eller öppna anmälningslänken du har fått från en arrangör.</p>
        ) : (
          <ul className="bk-orgs">
            {tournaments.map(item => (
              <li key={item.id}>
                <Link href={`/turneringar/${item.id}`}>
                  <strong>{item.name}</strong>
                  <span>{[
                    dateSpan(item.starts_on, item.ends_on), item.location, roleLabels[item.role],
                    item.status === "published" ? (item.registration_open ? "Anmälan öppen" : null) : tournamentStatusLabels[item.status],
                    item.pending ? `${item.pending} anmälningar väntar` : null,
                  ].filter(Boolean).join(" · ")}</span>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </section>
      <section className="wt-panel">
        <h2>Ny turnering</h2>
        {creating ? (
          <form className="wt-form" onSubmit={create}>
            <label>Namn<input value={form.name} onChange={event => setForm({ ...form, name: event.target.value })} maxLength={120} required placeholder="T.ex. Höstcupen 2026" /></label>
            <label>Sport (frivilligt)<input value={form.sport} onChange={event => setForm({ ...form, sport: event.target.value })} maxLength={60} placeholder="T.ex. Fotboll" /></label>
            <label>Plats (frivilligt)<input value={form.location} onChange={event => setForm({ ...form, location: event.target.value })} maxLength={200} placeholder="T.ex. Demovallen" /></label>
            <div className="bk-times">
              <label>Första dagen<input type="date" value={form.starts_on} onChange={event => setForm({ ...form, starts_on: event.target.value })} required /></label>
              <label>Sista dagen<input type="date" value={form.ends_on} min={form.starts_on || undefined} onChange={event => setForm({ ...form, ends_on: event.target.value })} /></label>
            </div>
            <div className="wt-actions">
              <button type="submit" className="wt-button" disabled={busy || !form.name.trim() || !form.starts_on}>Skapa</button>
              <button type="button" className="wt-button secondary" onClick={() => setCreating(false)}>Avbryt</button>
            </div>
          </form>
        ) : (
          <>
            <p>Lägg upp klasser, öppna anmälan och dela länken. Lag anmäler sig med sitt TeamZone-konto och du godkänner dem. Turneringen är ett utkast tills du publicerar den.</p>
            <button type="button" className="wt-button" onClick={() => setCreating(true)}>Skapa turnering</button>
          </>
        )}
      </section>
    </div>
  );
}
