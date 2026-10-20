"use client";

import { useEffect, useState } from "react";
import {
  bookingError, categoryLabels, categoryOrder, groupResources, kindLabels,
  type OrgKind, type OrgRole, type Organization, type Resource, type ResourceCategory,
} from "../../lib/booking";
import { useAccount } from "../account";

const emptyResource = { name: "", category: "pitch" as ResourceCategory, description: "", location: "", capacity: "", requires_approval: false, active: true };

export function ResourcesAdmin({ org, onChanged }: { org: Organization; onChanged: () => void }) {
  const { client } = useAccount();
  const [editing, setEditing] = useState<string | "new" | null>(null);
  const [form, setForm] = useState(emptyResource);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  const edit = (resource: Resource | null) => {
    setError("");
    setEditing(resource?.id ?? "new");
    setForm(resource ? {
      name: resource.name, category: resource.category, description: resource.description ?? "", location: resource.location ?? "",
      capacity: resource.capacity ? String(resource.capacity) : "", requires_approval: resource.requires_approval, active: resource.active,
    } : emptyResource);
  };

  const save = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!client) return;
    const capacity = form.capacity.trim() ? Number(form.capacity) : null;
    if (capacity !== null && (!Number.isInteger(capacity) || capacity < 1)) { setError("Antal platser är ett heltal från 1."); return; }
    setBusy(true);
    const { error: saveError } = await client.schema("api").rpc("save_booking_resource", {
      target_organization_id: org.id, target_resource_id: editing === "new" ? null : editing,
      resource_name: form.name, resource_category: form.category, resource_description: form.description || null,
      resource_location: form.location || null, resource_capacity: capacity,
      resource_requires_approval: form.requires_approval, resource_active: form.active,
    });
    setBusy(false);
    if (saveError) { setError(bookingError(saveError)); return; }
    setEditing(null);
    onChanged();
  };

  const groups = groupResources(org.resources, true);
  return (
    <section aria-label="Resurser">
      {editing ? (
        <form className="wt-panel wt-form" onSubmit={save}>
          <h2>{editing === "new" ? "Ny resurs" : "Ändra resurs"}</h2>
          <label>Namn<input value={form.name} onChange={event => setForm({ ...form, name: event.target.value })} maxLength={120} required placeholder="T.ex. Plan 1, Minibuss, Kamera 2" /></label>
          <label>Typ
            <select value={form.category} onChange={event => setForm({ ...form, category: event.target.value as ResourceCategory })}>
              {categoryOrder.map(value => <option key={value} value={value}>{categoryLabels[value]}</option>)}
            </select>
          </label>
          <label>Plats (frivilligt)<input value={form.location} onChange={event => setForm({ ...form, location: event.target.value })} maxLength={200} placeholder="T.ex. Demovallen" /></label>
          <label>Antal platser (frivilligt)<input inputMode="numeric" value={form.capacity} onChange={event => setForm({ ...form, capacity: event.target.value })} placeholder="T.ex. 9 i en minibuss" /></label>
          <label>Beskrivning (frivilligt)<textarea value={form.description} onChange={event => setForm({ ...form, description: event.target.value })} maxLength={2000} rows={3} /></label>
          <label className="wt-check"><input type="checkbox" checked={form.requires_approval} onChange={event => setForm({ ...form, requires_approval: event.target.checked })} /><span>Bokningar måste godkännas av en administratör</span></label>
          <label className="wt-check"><input type="checkbox" checked={form.active} onChange={event => setForm({ ...form, active: event.target.checked })} /><span>Går att boka</span></label>
          {error && <p role="alert" className="wt-error">{error}</p>}
          <div className="wt-actions">
            <button type="submit" className="wt-button" disabled={busy || !form.name.trim()}>Spara</button>
            <button type="button" className="wt-button secondary" onClick={() => setEditing(null)}>Avbryt</button>
          </div>
        </form>
      ) : (
        <div className="bk-admin-head">
          <p className="wt-small">Allt som går att boka: planer, hallar, omklädningsrum, lokaler, fordon och utrustning.</p>
          <button type="button" className="wt-button" onClick={() => edit(null)}>Ny resurs</button>
        </div>
      )}
      {groups.length === 0 && !editing && <div className="wt-panel"><p>Inga resurser än.</p></div>}
      {groups.map(group => (
        <div key={group.category} className="bk-group">
          <h2>{categoryLabels[group.category]}</h2>
          <ul className="bk-resource-list">
            {group.items.map(resource => (
              <li key={resource.id} data-inactive={!resource.active}>
                <div>
                  <strong>{resource.name}</strong>
                  <span>{[resource.location, resource.capacity ? `${resource.capacity} platser` : null, resource.requires_approval ? "Kräver godkännande" : "Bokas direkt", resource.active ? null : "Går inte att boka"].filter(Boolean).join(" · ")}</span>
                </div>
                <button type="button" className="wt-button secondary small" onClick={() => edit(resource)}>Ändra</button>
              </li>
            ))}
          </ul>
        </div>
      ))}
    </section>
  );
}

export function SettingsAdmin({ org, onChanged }: { org: Organization; onChanged: () => void }) {
  const { client } = useAccount();
  const [name, setName] = useState(org.name);
  const [kind, setKind] = useState<OrgKind>(org.kind);
  const [sport, setSport] = useState(org.sport ?? "");
  const [membersCanBook, setMembersCanBook] = useState(org.club_members_can_book);
  const [clubs, setClubs] = useState<{ club_id: string; name: string }[]>([]);
  const [club, setClub] = useState("");
  const [inviteRole, setInviteRole] = useState<OrgRole>("booker");
  const [link, setLink] = useState("");
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");

  useEffect(() => {
    client?.schema("api").rpc("list_booking_linkable_clubs").then(({ data }) => setClubs((data as { club_id: string; name: string }[]) ?? []));
  }, [client]);

  const run = async (call: () => PromiseLike<{ error: { message?: string } | null }>, done: string) => {
    setError(""); setMessage("");
    const { error: callError } = await call();
    if (callError) { setError(bookingError(callError)); return false; }
    setMessage(done);
    onChanged();
    return true;
  };

  const api = client?.schema("api");
  if (!api) return null;
  return (
    <div className="bk-settings">
      {message && <p className="wt-note" role="status">{message}</p>}
      {error && <p className="wt-error" role="alert">{error}</p>}
      <form className="wt-panel wt-form" onSubmit={event => {
        event.preventDefault();
        void run(() => api.rpc("update_booking_organization", { target_organization_id: org.id, org_name: name, org_kind: kind, org_sport: sport || null, members_can_book: membersCanBook }), "Sparat.");
      }}>
        <h2>Organisationen</h2>
        <label>Namn<input value={name} onChange={event => setName(event.target.value)} maxLength={120} required /></label>
        <label>Typ
          <select value={kind} onChange={event => setKind(event.target.value as OrgKind)}>
            {Object.entries(kindLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
          </select>
        </label>
        <label>Sport eller verksamhet<input value={sport} onChange={event => setSport(event.target.value)} maxLength={60} /></label>
        {org.teamzone_club_id && (
          <label className="wt-check"><input type="checkbox" checked={membersCanBook} onChange={event => setMembersCanBook(event.target.checked)} /><span>Klubbens ledare och funktionärer i TeamZone får boka utan inbjudan</span></label>
        )}
        <button type="submit" className="wt-button">Spara</button>
      </form>

      <section className="wt-panel">
        <h2>TeamZone</h2>
        {org.teamzone_club_id ? (
          <>
            <p>Kopplad till <strong>{org.teamzone_club_name}</strong>. Klubbens ledare kan boka för sina lag och koppla bokningen till en aktivitet, som då visar bokningen i appen.</p>
            <button type="button" className="wt-button secondary" onClick={() => {
              if (window.confirm("Ta bort kopplingen? Bokningar för klubbens lag tappar laget och aktiviteten.")) {
                void run(() => api.rpc("set_booking_organization_club", { target_organization_id: org.id, target_club_id: null }), "Kopplingen är borttagen.");
              }
            }}>Ta bort kopplingen</button>
          </>
        ) : clubs.length > 0 ? (
          <form className="wt-form" onSubmit={event => {
            event.preventDefault();
            if (club) void run(() => api.rpc("set_booking_organization_club", { target_organization_id: org.id, target_club_id: club }), "Organisationen är kopplad till klubben.");
          }}>
            <p>Koppla organisationen till en klubb där du är administratör i TeamZone. Då kan klubbens ledare boka för sina lag utan inbjudan.</p>
            <label>Klubb
              <select value={club} onChange={event => setClub(event.target.value)}>
                <option value="">Välj klubb</option>
                {clubs.map(item => <option key={item.club_id} value={item.club_id}>{item.name}</option>)}
              </select>
            </label>
            <button type="submit" className="wt-button" disabled={!club}>Koppla</button>
          </form>
        ) : (
          <p>Organisationen används utan TeamZone. En administratör för en klubb i TeamZone kan koppla den till klubben, så att klubbens ledare kan boka för sina lag.</p>
        )}
      </section>

      <section className="wt-panel">
        <h2>Medlemmar</h2>
        <ul className="bk-resource-list">
          {(org.members ?? []).map(member => (
            <li key={member.profile_id}>
              <div><strong>{member.name ?? "Okänd"}{member.is_self ? " (du)" : ""}</strong><span>{member.role === "admin" ? "Administratör" : "Bokare"}</span></div>
              {!member.is_self && (
                <div className="wt-actions">
                  <button type="button" className="wt-button secondary small" onClick={() => void run(() => api.rpc("set_booking_member", { target_organization_id: org.id, target_profile_id: member.profile_id, member_role: member.role === "admin" ? "booker" : "admin" }), "Rollen är ändrad.")}>
                    {member.role === "admin" ? "Gör till bokare" : "Gör till administratör"}
                  </button>
                  <button type="button" className="wt-button secondary small" onClick={() => {
                    if (window.confirm(`Ta bort ${member.name ?? "medlemmen"}?`)) void run(() => api.rpc("set_booking_member", { target_organization_id: org.id, target_profile_id: member.profile_id, member_role: null }), "Medlemmen är borttagen.");
                  }}>Ta bort</button>
                </div>
              )}
            </li>
          ))}
        </ul>
        {org.teamzone_club_id && org.club_members_can_book && <p className="wt-small">Klubbens ledare och funktionärer i TeamZone kan boka utan att stå med här.</p>}
        <h3>Bjud in</h3>
        <div className="wt-form">
          <label>Roll
            <select value={inviteRole} onChange={event => setInviteRole(event.target.value as OrgRole)}>
              <option value="booker">Bokare: bokar och ser bokningar</option>
              <option value="admin">Administratör: hanterar resurser, medlemmar och godkännanden</option>
            </select>
          </label>
          <button type="button" className="wt-button" onClick={async () => {
            setError(""); setLink("");
            const { data, error: inviteError } = await api.rpc("create_booking_invitation", { target_organization_id: org.id, invite_role: inviteRole });
            if (inviteError) { setError(bookingError(inviteError)); return; }
            setLink(`${window.location.origin}/bokningar?inbjudan=${data}`);
          }}>Skapa inbjudningslänk</button>
          {link && (
            <div className="bk-invite">
              <input readOnly value={link} onFocus={event => event.target.select()} aria-label="Inbjudningslänk" />
              <button type="button" className="wt-button secondary small" onClick={() => void navigator.clipboard?.writeText(link).then(() => setMessage("Länken är kopierad."))}>Kopiera</button>
              <p className="wt-small">Länken gäller i 14 dagar och för en person. Den som öppnar den loggar in med sitt TeamZone-konto, eller skapar ett.</p>
            </div>
          )}
        </div>
      </section>
    </div>
  );
}
