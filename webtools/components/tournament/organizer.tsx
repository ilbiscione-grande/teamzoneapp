"use client";

import { useCallback, useEffect, useState } from "react";
import {
  feeLabel, formatLabels, placesLeft, registrationsByClass, registrationStatusLabels, roleLabels, tournamentError,
  tournamentStatusLabels, wholeNumber, type ClassFormat, type Registration, type Tournament, type TournamentClass,
  type TournamentRole, type TournamentStatus,
} from "../../lib/tournament";
import { useAccount } from "../account";

type Call = () => PromiseLike<{ error: { message?: string } | null }>;

/** Runs an API call; the sentence for its error, or the done message. */
function useRunner(onChanged: () => void) {
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const run = async (call: Call, done: string) => {
    setError(""); setMessage("");
    const { error: callError } = await call();
    if (callError) { setError(tournamentError(callError)); return false; }
    setMessage(done);
    onChanged();
    return true;
  };
  return { run, message, error, setError, setMessage };
}

function Notices({ message, error }: { message: string; error: string }) {
  return (
    <>
      {message && <p className="wt-note" role="status">{message}</p>}
      {error && <p className="wt-error" role="alert">{error}</p>}
    </>
  );
}

/** Registrations by class: approve or decline, tick off fees. Officials read. */
export function RegistrationsAdmin({ tournament, onChanged }: { tournament: Tournament; onChanged: () => void }) {
  const { client } = useAccount();
  const [registrations, setRegistrations] = useState<Registration[] | null>(null);
  const [showAll, setShowAll] = useState(false);
  const organizer = tournament.role === "organizer";
  const load = useCallback(async () => {
    if (!client) return;
    const { data, error: loadError } = await client.schema("api").rpc("list_tournament_registrations", { target_tournament_id: tournament.id });
    if (loadError) { setError(tournamentError(loadError)); return; }
    setRegistrations(data as Registration[]);
  }, [client, tournament.id]);
  const { run, message, error, setError } = useRunner(() => { void load(); onChanged(); });
  useEffect(() => { void load(); }, [load]);
  const api = client?.schema("api");
  if (!api) return null;
  if (!registrations) return <><Notices message={message} error={error} /><p className="wt-status">Laddar…</p></>;
  const visible = showAll ? registrations : registrations.filter(item => item.status === "pending" || item.status === "approved");
  return (
    <section aria-label="Anmälningar">
      <Notices message={message} error={error} />
      <div className="bk-admin-head">
        <p className="wt-small">{registrations.length === 0 ? "Inga anmälningar än." : `${registrations.filter(item => item.status === "approved").length} godkända, ${registrations.filter(item => item.status === "pending").length} väntar.`}</p>
        <label className="wt-check"><input type="checkbox" checked={showAll} onChange={event => setShowAll(event.target.checked)} /><span>Visa nekade och återtagna</span></label>
      </div>
      {registrationsByClass(tournament.classes, visible).map(({ item, registrations: rows }) => (
        <div key={item.id} className="bk-group">
          <h2>{item.name} <span className="tp-count">{[`${item.approved}${item.max_teams ? ` av ${item.max_teams}` : ""} lag`, feeLabel(item.fee_sek)].filter(Boolean).join(" · ")}</span></h2>
          {rows.length === 0 ? <p className="wt-small">Inga anmälningar i klassen.</p> : (
            <ul className="bk-bookings">
              {rows.map(row => (
                <li key={row.id} className="bk-booking" data-status={row.status === "pending" ? "pending" : undefined}>
                  <div className="bk-booking-time"><strong>{row.team_name}</strong>{row.club_name && <span>{row.club_name}</span>}</div>
                  <div className="bk-booking-body">
                    <span>{[row.contact_name, row.contact_email, row.contact_phone].filter(Boolean).join(" · ")}</span>
                    {row.notes && <span className="tp-text">”{row.notes}”</span>}
                    <span>{[
                      registrationStatusLabels[row.status],
                      item.fee_sek ? (row.paid ? "Betald" : "Ej betald") : null,
                      row.registered_by_name ? `anmäld av ${row.registered_by_name}` : null,
                      new Date(row.created_at).toLocaleDateString("sv-SE", { day: "numeric", month: "short" }),
                    ].filter(Boolean).join(" · ")}</span>
                  </div>
                  {organizer && (
                    <div className="bk-booking-actions">
                      {row.status === "pending" && <button type="button" className="wt-button small" disabled={placesLeft(item) === 0}
                        onClick={() => void run(() => api.rpc("decide_tournament_registration", { target_registration_id: row.id, approve: true }), `${row.team_name} är godkänt.`)}>Godkänn</button>}
                      {row.status === "pending" && <button type="button" className="wt-button secondary small"
                        onClick={() => void run(() => api.rpc("decide_tournament_registration", { target_registration_id: row.id, approve: false }), `${row.team_name} är nekat.`)}>Neka</button>}
                      {row.status === "approved" && item.fee_sek ? <button type="button" className="wt-button secondary small"
                        onClick={() => void run(() => api.rpc("set_tournament_registration_paid", { target_registration_id: row.id, is_paid: !row.paid }), row.paid ? "Markerad som ej betald." : "Markerad som betald.")}>{row.paid ? "Ångra betald" : "Betald"}</button> : null}
                      {row.status === "approved" && <button type="button" className="wt-button secondary small" onClick={() => {
                        if (window.confirm(`Stryka ${row.team_name} ur turneringen?`)) void run(() => api.rpc("withdraw_tournament_registration", { target_registration_id: row.id }), `${row.team_name} är struket.`);
                      }}>Stryk</button>}
                    </div>
                  )}
                </li>
              ))}
            </ul>
          )}
        </div>
      ))}
    </section>
  );
}

const emptyClass = { name: "", description: "", format: "groups_playoff" as ClassFormat, max_teams: "", fee_sek: "", match_minutes: "", sort_order: "" };

export function ClassesAdmin({ tournament, onChanged }: { tournament: Tournament; onChanged: () => void }) {
  const { client } = useAccount();
  const [editing, setEditing] = useState<string | "new" | null>(null);
  const [form, setForm] = useState(emptyClass);
  const { run, message, error, setError } = useRunner(onChanged);

  const edit = (item: TournamentClass | null) => {
    setError("");
    setEditing(item?.id ?? "new");
    setForm(item ? {
      name: item.name, description: item.description ?? "", format: item.format,
      max_teams: item.max_teams ? String(item.max_teams) : "", fee_sek: item.fee_sek === null ? "" : String(item.fee_sek),
      match_minutes: item.match_minutes ? String(item.match_minutes) : "", sort_order: String(item.sort_order),
    } : { ...emptyClass, sort_order: String(tournament.classes.length + 1) });
  };

  const save = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!client) return;
    const maxTeams = wholeNumber(form.max_teams, 2, 256);
    const fee = wholeNumber(form.fee_sek, 0, 1000000);
    const minutes = wholeNumber(form.match_minutes, 1, 240);
    if (maxTeams === "invalid") { setError("Max antal lag är ett heltal från 2 till 256."); return; }
    if (fee === "invalid") { setError("Avgiften är hela kronor."); return; }
    if (minutes === "invalid") { setError("Matchtiden är hela minuter, högst 240."); return; }
    const saved = await run(() => client.schema("api").rpc("save_tournament_class", {
      target_tournament_id: tournament.id, target_class_id: editing === "new" ? null : editing,
      class_name: form.name, class_description: form.description || null, class_format: form.format,
      class_max_teams: maxTeams, class_fee_sek: fee, class_match_minutes: minutes,
      class_sort_order: Number(form.sort_order) || 0,
    }), "Klassen är sparad.");
    if (saved) setEditing(null);
  };

  return (
    <section aria-label="Klasser">
      <Notices message={message} error={editing ? "" : error} />
      {editing ? (
        <form className="wt-panel wt-form" onSubmit={save}>
          <h2>{editing === "new" ? "Ny klass" : "Ändra klass"}</h2>
          <label>Namn<input value={form.name} onChange={event => setForm({ ...form, name: event.target.value })} maxLength={60} required placeholder="T.ex. P12, F13, Herr" /></label>
          <label>Beskrivning (frivilligt)<input value={form.description} onChange={event => setForm({ ...form, description: event.target.value })} maxLength={500} placeholder="T.ex. Födda 2014, 7 mot 7" /></label>
          <label>Spelform
            <select value={form.format} onChange={event => setForm({ ...form, format: event.target.value as ClassFormat })}>
              {Object.entries(formatLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
            </select>
          </label>
          <div className="bk-times">
            <label>Max antal lag (frivilligt)<input inputMode="numeric" value={form.max_teams} onChange={event => setForm({ ...form, max_teams: event.target.value })} placeholder="Ingen gräns" /></label>
            <label>Anmälningsavgift, kr (frivilligt)<input inputMode="numeric" value={form.fee_sek} onChange={event => setForm({ ...form, fee_sek: event.target.value })} placeholder="T.ex. 1500" /></label>
            <label>Matchtid, minuter (frivilligt)<input inputMode="numeric" value={form.match_minutes} onChange={event => setForm({ ...form, match_minutes: event.target.value })} placeholder="T.ex. 15" /></label>
            <label>Ordning<input inputMode="numeric" value={form.sort_order} onChange={event => setForm({ ...form, sort_order: event.target.value })} /></label>
          </div>
          {form.format === "pool" && <p className="wt-small">Poolspel: matcher utan resultat och tabeller, som i de yngsta åldrarna.</p>}
          {error && <p role="alert" className="wt-error">{error}</p>}
          <div className="wt-actions">
            <button type="submit" className="wt-button" disabled={!form.name.trim()}>Spara</button>
            <button type="button" className="wt-button secondary" onClick={() => setEditing(null)}>Avbryt</button>
          </div>
        </form>
      ) : (
        <div className="bk-admin-head">
          <p className="wt-small">Varje klass spelas för sig: åldersklasser, damer och herrar eller nivåer.</p>
          <button type="button" className="wt-button" onClick={() => edit(null)}>Ny klass</button>
        </div>
      )}
      {tournament.classes.length === 0 && !editing && <div className="wt-panel"><p>Inga klasser än. Lägg upp minst en innan du öppnar anmälan.</p></div>}
      <ul className="bk-resource-list">
        {tournament.classes.map(item => (
          <li key={item.id}>
            <div>
              <strong>{item.name}</strong>
              <span>{[item.description, formatLabels[item.format], item.max_teams ? `max ${item.max_teams} lag` : null, feeLabel(item.fee_sek), item.match_minutes ? `${item.match_minutes} min` : null].filter(Boolean).join(" · ")}</span>
              <span>{item.approved} godkända · {item.pending} väntar</span>
            </div>
            <div className="wt-actions">
              <button type="button" className="wt-button secondary small" onClick={() => edit(item)}>Ändra</button>
              {item.approved + item.pending === 0 && client && (
                <button type="button" className="wt-button secondary small" onClick={() => {
                  if (window.confirm(`Ta bort klassen ${item.name}?`)) void run(() => client.schema("api").rpc("delete_tournament_class", { target_class_id: item.id }), "Klassen är borttagen.");
                }}>Ta bort</button>
              )}
            </div>
          </li>
        ))}
      </ul>
    </section>
  );
}

/** A local "2026-11-01T18:00" for a datetime-local field. */
function localInput(value: string | null): string {
  if (!value) return "";
  const date = new Date(value);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

export function SettingsAdmin({ tournament, onChanged }: { tournament: Tournament; onChanged: () => void }) {
  const { client } = useAccount();
  const [form, setForm] = useState({
    name: tournament.name, sport: tournament.sport ?? "", location: tournament.location ?? "",
    starts_on: tournament.starts_on, ends_on: tournament.ends_on, description: tournament.description ?? "",
    contact_email: tournament.contact_email ?? "", payment_info: tournament.payment_info ?? "",
    status: tournament.status, registration_open: tournament.registration_open,
    registration_closes_at: localInput(tournament.registration_closes_at),
  });
  const { run, message, error } = useRunner(onChanged);
  if (!client) return null;
  const save = (event: React.FormEvent) => {
    event.preventDefault();
    void run(() => client.schema("api").rpc("update_tournament", {
      target_tournament_id: tournament.id, tournament_name: form.name, tournament_sport: form.sport || null,
      tournament_location: form.location || null, tournament_starts_on: form.starts_on, tournament_ends_on: form.ends_on,
      tournament_description: form.description || null, tournament_contact_email: form.contact_email || null,
      tournament_payment_info: form.payment_info || null, tournament_status: form.status,
      tournament_registration_open: form.registration_open && form.status === "published",
      tournament_registration_closes_at: form.registration_closes_at ? new Date(form.registration_closes_at).toISOString() : null,
    }), "Sparat.");
  };
  return (
    <form className="wt-panel wt-form" onSubmit={save}>
      <Notices message={message} error={error} />
      <h2>Turneringen</h2>
      <label>Namn<input value={form.name} onChange={event => setForm({ ...form, name: event.target.value })} maxLength={120} required /></label>
      <div className="bk-times">
        <label>Sport<input value={form.sport} onChange={event => setForm({ ...form, sport: event.target.value })} maxLength={60} /></label>
        <label>Plats<input value={form.location} onChange={event => setForm({ ...form, location: event.target.value })} maxLength={200} /></label>
        <label>Första dagen<input type="date" value={form.starts_on} onChange={event => setForm({ ...form, starts_on: event.target.value })} required /></label>
        <label>Sista dagen<input type="date" value={form.ends_on} min={form.starts_on} onChange={event => setForm({ ...form, ends_on: event.target.value })} required /></label>
      </div>
      <label>Om turneringen (frivilligt)<textarea value={form.description} onChange={event => setForm({ ...form, description: event.target.value })} maxLength={4000} rows={5} placeholder="Regler, spelformer, mat och boende..." /></label>
      <label>Kontakt-e-post (frivilligt)<input type="email" value={form.contact_email} onChange={event => setForm({ ...form, contact_email: event.target.value })} maxLength={200} /></label>
      <label>Betalning av avgifter (frivilligt)<textarea value={form.payment_info} onChange={event => setForm({ ...form, payment_info: event.target.value })} maxLength={1000} rows={2} placeholder="T.ex. Swish 123 456 78 90, märk med lagets namn" /></label>
      <p className="wt-small">Avgifterna betalas utanför Webtools. Du bockar av betalda lag under Anmälningar.</p>
      <h3>Publicering och anmälan</h3>
      <label>Status
        <select value={form.status} onChange={event => setForm({ ...form, status: event.target.value as TournamentStatus })}>
          {(Object.keys(tournamentStatusLabels) as TournamentStatus[]).map(value => <option key={value} value={value}>{tournamentStatusLabels[value]}</option>)}
        </select>
      </label>
      <label className="wt-check"><input type="checkbox" checked={form.registration_open && form.status === "published"} disabled={form.status !== "published"} onChange={event => setForm({ ...form, registration_open: event.target.checked })} /><span>Anmälan är öppen</span></label>
      <label>Anmälan stänger (frivilligt)<input type="datetime-local" value={form.registration_closes_at} onChange={event => setForm({ ...form, registration_closes_at: event.target.value })} /></label>
      {form.status === "draft" && tournament.classes.length === 0 && <p className="wt-small">Lägg upp klasserna innan du publicerar.</p>}
      <button type="submit" className="wt-button">Spara</button>
    </form>
  );
}

export function StaffAdmin({ tournament, onChanged }: { tournament: Tournament; onChanged: () => void }) {
  const { client } = useAccount();
  const [role, setRole] = useState<TournamentRole>("official");
  const [link, setLink] = useState("");
  const { run, message, error, setError, setMessage } = useRunner(onChanged);
  const api = client?.schema("api");
  if (!api) return null;
  return (
    <section className="wt-panel">
      <Notices message={message} error={error} />
      <h2>Arrangörer och funktionärer</h2>
      <ul className="bk-resource-list">
        {(tournament.staff ?? []).map(member => (
          <li key={member.profile_id}>
            <div><strong>{member.name ?? "Okänd"}{member.is_self ? " (du)" : ""}</strong><span>{roleLabels[member.role]}</span></div>
            {!member.is_self && (
              <div className="wt-actions">
                <button type="button" className="wt-button secondary small" onClick={() => {
                  if (window.confirm(`Ta bort ${member.name ?? "personen"}?`)) void run(() => api.rpc("remove_tournament_staff", { target_tournament_id: tournament.id, target_profile_id: member.profile_id }), "Borttagen.");
                }}>Ta bort</button>
              </div>
            )}
          </li>
        ))}
      </ul>
      <p className="wt-small">Funktionärer ser anmälningarna och kommer att föra in resultat när spelschemat finns. Arrangörer hanterar allt.</p>
      <h3>Bjud in</h3>
      <div className="wt-form">
        <label>Roll
          <select value={role} onChange={event => setRole(event.target.value as TournamentRole)}>
            <option value="official">Funktionär: sekretariat, planansvarig</option>
            <option value="organizer">Arrangör: hanterar turneringen</option>
          </select>
        </label>
        <button type="button" className="wt-button" onClick={async () => {
          setError(""); setLink("");
          const { data, error: inviteError } = await api.rpc("create_tournament_staff_invitation", { target_tournament_id: tournament.id, invite_role: role });
          if (inviteError) { setError(tournamentError(inviteError)); return; }
          setLink(`${window.location.origin}/turneringar?inbjudan=${data}`);
        }}>Skapa inbjudningslänk</button>
        {link && (
          <div className="bk-invite">
            <input readOnly value={link} onFocus={event => event.target.select()} aria-label="Inbjudningslänk" />
            <button type="button" className="wt-button secondary small" onClick={() => void navigator.clipboard?.writeText(link).then(() => setMessage("Länken är kopierad."))}>Kopiera</button>
            <p className="wt-small">Länken gäller i 14 dagar och för en person.</p>
          </div>
        )}
      </div>
    </section>
  );
}
