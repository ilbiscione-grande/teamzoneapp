"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import {
  dateSpan, feeLabel, formatLabels, placesLeft, registrationStatusLabels, roleLabels, tournamentError,
  tournamentStatusLabels, type Registration, type Tournament,
} from "../../lib/tournament";
import { useAccount } from "../account";
import { ClassesAdmin, RegistrationsAdmin, SettingsAdmin, StaffAdmin } from "./organizer";

type Tab = "overview" | "registrations" | "classes" | "settings" | "staff";

export function TournamentView({ id }: { id: string }) {
  const { client } = useAccount();
  const [tournament, setTournament] = useState<Tournament | null>(null);
  const [error, setError] = useState("");
  const [tab, setTab] = useState<Tab>("overview");

  const load = useCallback(async () => {
    if (!client) return;
    const { data, error: loadError } = await client.schema("api").rpc("get_tournament", { target_tournament_id: id });
    if (loadError) { setError(tournamentError(loadError)); return; }
    setTournament(data as Tournament);
  }, [client, id]);

  useEffect(() => { void load(); }, [load]);

  if (error) return <section className="wt-panel"><p role="alert" className="wt-error">{error}</p><Link className="wt-link" href="/turneringar">Till dina turneringar</Link></section>;
  if (!tournament) return <p className="wt-status">Laddar…</p>;
  const organizer = tournament.role === "organizer";
  const pending = tournament.classes.reduce((sum, item) => sum + item.pending, 0);
  const tabs: [Tab, string][] = tournament.role ? [
    ["overview", "Översikt"],
    ["registrations", pending && organizer ? `Anmälningar (${pending})` : "Anmälningar"],
    ...(organizer ? [["classes", "Klasser"], ["settings", "Inställningar"], ["staff", "Funktionärer"]] as [Tab, string][] : []),
  ] : [];
  return (
    <div className="bk-org">
      <div className="bk-org-head">
        <div>
          <p className="wt-kicker dark">Turneringsplanerare</p>
          <h1>{tournament.name}</h1>
          <p className="wt-small">
            {[dateSpan(tournament.starts_on, tournament.ends_on), tournament.location, tournament.sport,
              tournament.role ? roleLabels[tournament.role] : null,
              tournament.status !== "published" ? tournamentStatusLabels[tournament.status] : null].filter(Boolean).join(" · ")}
          </p>
        </div>
        <Link className="wt-link" href="/turneringar">Dina turneringar</Link>
      </div>
      {tabs.length > 0 && (
        <div className="bk-tabs" role="tablist" aria-label="Turneringen">
          {tabs.map(([value, label]) => (
            <button key={value} type="button" role="tab" aria-selected={tab === value} onClick={() => setTab(value)}>{label}</button>
          ))}
        </div>
      )}
      {tab === "overview" && <Overview tournament={tournament} onChanged={load} />}
      {tab === "registrations" && tournament.role && <RegistrationsAdmin tournament={tournament} onChanged={load} />}
      {tab === "classes" && organizer && <ClassesAdmin tournament={tournament} onChanged={load} />}
      {tab === "settings" && organizer && <SettingsAdmin tournament={tournament} onChanged={load} />}
      {tab === "staff" && organizer && <StaffAdmin tournament={tournament} onChanged={load} />}
    </div>
  );
}

/** What everyone sees: the tournament, its classes, registering and your teams. */
function Overview({ tournament, onChanged }: { tournament: Tournament; onChanged: () => void }) {
  const [link, setLink] = useState("");
  useEffect(() => { setLink(`${window.location.origin}/turneringar/${tournament.id}`); }, [tournament.id]);
  const organizer = tournament.role === "organizer";
  return (
    <div className="tp-overview">
      {organizer && tournament.status === "draft" && (
        <p className="wt-note">Turneringen är ett utkast och syns bara för dig och funktionärerna. Lägg upp klasserna och publicera den under Inställningar.</p>
      )}
      {organizer && tournament.status === "published" && (
        <section className="wt-panel">
          <h2>Anmälningslänk</h2>
          <p>{tournament.registration_is_open ? "Dela länken med lagen. De anmäler sig med sitt TeamZone-konto, och du godkänner dem under Anmälningar." : "Anmälan är stängd. Öppna den under Inställningar."}</p>
          <div className="bk-invite">
            <input readOnly value={link} onFocus={event => event.target.select()} aria-label="Anmälningslänk" />
            <button type="button" className="wt-button secondary small" onClick={() => void navigator.clipboard?.writeText(link)}>Kopiera</button>
          </div>
        </section>
      )}
      {(tournament.description || tournament.contact_email) && (
        <section className="wt-panel">
          <h2>Om turneringen</h2>
          {tournament.description && <p className="tp-text">{tournament.description}</p>}
          <p className="wt-small">{[tournament.organizer_name ? `Arrangör: ${tournament.organizer_name}` : null, tournament.contact_email ? `Kontakt: ${tournament.contact_email}` : null].filter(Boolean).join(" · ")}</p>
        </section>
      )}
      <section className="wt-panel">
        <h2>Klasser</h2>
        {tournament.classes.length === 0 ? <p>Inga klasser än.</p> : (
          <ul className="bk-resource-list">
            {tournament.classes.map(item => {
              const left = placesLeft(item);
              return (
                <li key={item.id}>
                  <div>
                    <strong>{item.name}</strong>
                    <span>{[item.description, formatLabels[item.format], item.match_minutes ? `${item.match_minutes} min matcher` : null, feeLabel(item.fee_sek)].filter(Boolean).join(" · ")}</span>
                    <span>{[`${item.approved} lag godkända`, left === null ? null : left === 0 ? "Full" : `${left} platser kvar`].filter(Boolean).join(" · ")}</span>
                  </div>
                </li>
              );
            })}
          </ul>
        )}
      </section>
      <MyRegistrations tournament={tournament} onChanged={onChanged} />
      <RegisterForm tournament={tournament} onRegistered={onChanged} />
    </div>
  );
}

function MyRegistrations({ tournament, onChanged }: { tournament: Tournament; onChanged: () => void }) {
  const { client } = useAccount();
  const [error, setError] = useState("");
  const mine = tournament.my_registrations.filter(item => item.status !== "withdrawn");
  if (mine.length === 0) return null;
  const withdraw = async (registration: Registration) => {
    if (!client || !window.confirm(`Ta tillbaka anmälan för ${registration.team_name}?`)) return;
    const { error: withdrawError } = await client.schema("api").rpc("withdraw_tournament_registration", { target_registration_id: registration.id });
    if (withdrawError) { setError(tournamentError(withdrawError)); return; }
    onChanged();
  };
  const fees = mine.some(item => item.status !== "declined" && !item.paid
    && (tournament.classes.find(c => c.id === item.class_id)?.fee_sek ?? 0) > 0);
  return (
    <section className="wt-panel">
      <h2>Dina anmälda lag</h2>
      {error && <p role="alert" className="wt-error">{error}</p>}
      <ul className="bk-bookings">
        {mine.map(item => {
          const fee = tournament.classes.find(c => c.id === item.class_id)?.fee_sek ?? null;
          return (
            <li key={item.id} className="bk-booking" data-status={item.status === "pending" ? "pending" : undefined}>
              <div className="bk-booking-time"><strong>{item.class_name}</strong></div>
              <div className="bk-booking-body">
                <strong>{item.team_name}</strong>
                <span>{[item.club_name, registrationStatusLabels[item.status], fee ? (item.paid ? "Avgiften är betald" : `Avgift ${feeLabel(fee)}`) : null].filter(Boolean).join(" · ")}</span>
              </div>
              <div className="bk-booking-actions">
                {(item.status === "pending" || item.status === "approved") && (
                  <button type="button" className="wt-button secondary small" onClick={() => void withdraw(item)}>Ta tillbaka</button>
                )}
              </div>
            </li>
          );
        })}
      </ul>
      {fees && tournament.payment_info && <p className="wt-small tp-text">Betalning: {tournament.payment_info}</p>}
    </section>
  );
}

const emptyRegistration = { class_id: "", team_name: "", club_name: "", contact_name: "", contact_email: "", contact_phone: "", notes: "" };

function RegisterForm({ tournament, onRegistered }: { tournament: Tournament; onRegistered: () => void }) {
  const { client, session, displayName } = useAccount();
  const [form, setForm] = useState(emptyRegistration);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const open = tournament.classes.filter(item => placesLeft(item) !== 0);

  // The contact is you, unless you write someone else.
  const email = session?.user.email ?? "";
  useEffect(() => {
    setForm(current => ({
      ...current,
      contact_email: current.contact_email || email,
      contact_name: current.contact_name || displayName,
    }));
  }, [email, displayName]);

  if (!tournament.registration_is_open) {
    return tournament.status === "published"
      ? <section className="wt-panel"><h2>Anmälan</h2><p>Anmälan är stängd.</p></section>
      : null;
  }
  const submit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!client) return;
    setBusy(true); setError(""); setMessage("");
    const { error: registerError } = await client.schema("api").rpc("register_tournament_team", {
      target_class_id: form.class_id, registration_team_name: form.team_name, registration_club_name: form.club_name || null,
      registration_contact_name: form.contact_name, registration_contact_email: form.contact_email,
      registration_contact_phone: form.contact_phone || null, registration_notes: form.notes || null,
    });
    setBusy(false);
    if (registerError) { setError(tournamentError(registerError)); return; }
    setMessage(`${form.team_name} är anmält. Arrangören godkänner anmälan.`);
    setForm({ ...emptyRegistration, contact_name: form.contact_name, contact_email: form.contact_email, contact_phone: form.contact_phone, club_name: form.club_name });
    onRegistered();
  };
  return (
    <section className="wt-panel">
      <h2>Anmäl lag</h2>
      {message && <p className="wt-note" role="status">{message}</p>}
      {open.length === 0 ? <p>Alla klasser är fulla.</p> : (
        <form className="wt-form" onSubmit={submit}>
          <label>Klass
            <select value={form.class_id} onChange={event => setForm({ ...form, class_id: event.target.value })} required>
              <option value="">Välj klass</option>
              {open.map(item => <option key={item.id} value={item.id}>{[item.name, item.description, feeLabel(item.fee_sek)].filter(Boolean).join(" · ")}</option>)}
            </select>
          </label>
          <label>Lagets namn<input value={form.team_name} onChange={event => setForm({ ...form, team_name: event.target.value })} maxLength={120} required placeholder="T.ex. Demoklubben P12 Blå" /></label>
          <label>Klubb eller förening (frivilligt)<input value={form.club_name} onChange={event => setForm({ ...form, club_name: event.target.value })} maxLength={120} /></label>
          <label>Kontaktperson<input value={form.contact_name} onChange={event => setForm({ ...form, contact_name: event.target.value })} maxLength={120} required /></label>
          <div className="bk-times">
            <label>E-post<input type="email" value={form.contact_email} onChange={event => setForm({ ...form, contact_email: event.target.value })} maxLength={200} required /></label>
            <label>Telefon (frivilligt)<input type="tel" value={form.contact_phone} onChange={event => setForm({ ...form, contact_phone: event.target.value })} maxLength={40} /></label>
          </div>
          <label>Meddelande till arrangören (frivilligt)<textarea value={form.notes} onChange={event => setForm({ ...form, notes: event.target.value })} maxLength={2000} rows={3} /></label>
          {error && <p role="alert" className="wt-error">{error}</p>}
          <button type="submit" className="wt-button" disabled={busy || !form.class_id || !form.team_name.trim() || !form.contact_name.trim()}>Anmäl</button>
          {tournament.registration_closes_at && <p className="wt-small">Anmälan stänger {new Date(tournament.registration_closes_at).toLocaleString("sv-SE", { day: "numeric", month: "long", hour: "2-digit", minute: "2-digit" })}.</p>}
        </form>
      )}
    </section>
  );
}
