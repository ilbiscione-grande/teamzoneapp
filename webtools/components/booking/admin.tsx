"use client";

import { useEffect, useState } from "react";
import {
  resourcePath, resourceCanContain, bookingError, categoryLabels, categoryOrder, kindLabels,
  type ResourceAvailability, type ResourceOwnership, type OrgKind, type OrgRole, type Organization, type Resource, type ResourceCategory,
} from "../../lib/booking";
import { ResourceHours } from "./resource-hours";
import { useAccount } from "../account";
import { resourceAdminGroups, type ResourceStatusFilter } from "../../lib/resource-admin";

const emptyAvailability: ResourceAvailability = { mode: "always", weekly: [], exceptions: [] };
const emptyResource = { pitch_setup: "", indefinite: false, parent_resource_id: "", availability: emptyAvailability, ownership_kind: "owned" as ResourceOwnership, owner_name: "", timezone: "Europe/Stockholm", available_from: "", available_until: "", name: "", category: "pitch" as ResourceCategory, description: "", location: "", capacity: "", requires_approval: false, active: true };

export function ResourcesAdmin({ org, onChanged }: { org: Organization; onChanged: () => void }) {
  const { client } = useAccount();
  const [editing, setEditing] = useState<string | "new" | null>(null);
  const [form, setForm] = useState(emptyResource);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [query, setQuery] = useState("");
  const [category, setCategory] = useState<ResourceCategory | "all">("all");
  const [status, setStatus] = useState<ResourceStatusFilter>("all");

  const edit = (resource: Resource | null, parent?: Resource) => {
    setError("");
    setEditing(resource?.id ?? "new");
    setForm(resource ? {
      pitch_setup: "", indefinite: !!resource.available_from && !resource.available_until,
      parent_resource_id: resource.parent_resource_id ?? "",
      availability: resource.availability ?? emptyAvailability,
      ownership_kind: resource.ownership_kind ?? "unspecified", owner_name: resource.owner_name ?? "", timezone: resource.timezone ?? "Europe/Stockholm",
      available_from: resource.available_from ?? "", available_until: resource.available_until ?? "",
      name: resource.name, category: resource.category, description: resource.description ?? "", location: resource.location ?? "",
      capacity: resource.capacity ? String(resource.capacity) : "", requires_approval: resource.requires_approval, active: resource.active,
    } : { ...emptyResource, parent_resource_id: parent?.id ?? "", category: parent?.category ?? "pitch",
      location: parent?.location ?? "", timezone: parent?.timezone ?? "Europe/Stockholm",
      ownership_kind: parent?.ownership_kind ?? "owned", owner_name: parent?.owner_name ?? "",
      available_from: parent?.available_from ?? "", available_until: parent?.available_until ?? "", indefinite: !!parent?.available_from && !parent?.available_until,
      requires_approval: parent?.requires_approval ?? false });
  };

  const save = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!client || busy) return;
    const capacity = form.capacity.trim() ? Number(form.capacity) : null;
    if (capacity !== null && (!Number.isInteger(capacity) || capacity < 1)) { setError("Antal platser är ett heltal från 1."); return; }
    if (form.ownership_kind === "external" && (!form.owner_name.trim() || !form.available_from || (!form.indefinite && !form.available_until))) {
      setError("Ange resursägare, startdatum och slutdatum eller välj tills vidare."); return;
    }
    if ((!!form.available_until && !form.available_from) || (!form.indefinite && !!form.available_from && !form.available_until) || (!form.indefinite && form.available_from && form.available_until < form.available_from)) {
      setError("Ange både från- och tilldatum, med slutdatum samma dag eller senare."); return;
    }
    const windows = [...form.availability.weekly, ...form.availability.exceptions.flatMap(item => item.windows)];
    if (windows.some(window => window.end <= window.start) || form.availability.exceptions.some(item => !item.date)
      || new Set(form.availability.exceptions.map(item => item.date)).size !== form.availability.exceptions.length) {
      setError(bookingError({ message: "invalid_availability" })); return;
    }
    setError("");
    setBusy(true);
    const { error: saveError } = await client.schema("api").rpc("save_booking_resource_v2", {
      target_organization_id: org.id, target_resource_id: editing === "new" ? null : editing,
      expected_revision: editing === "new" ? null : org.resources.find(item => item.id === editing)?.revision ?? null,
      details: { ...form, parent_resource_id: form.parent_resource_id || null, capacity, description: form.description || null, location: form.location || null,
        owner_name: form.owner_name.trim() || null, available_from: form.available_from || null, available_until: form.indefinite ? null : form.available_until || null },
    });
    setBusy(false);
    if (saveError) { setError(bookingError(saveError)); return; }
    setEditing(null);
    onChanged();
  };

  const groups = resourceAdminGroups(org.resources,query,category,status);
  const filtered = !!query.trim() || category !== "all" || status !== "all";
  const matches = groups.reduce((count,group) => count + group.matchingIds.length,0);
  const parent = org.resources.find(resource => resource.id === form.parent_resource_id);
  return (
    <section aria-label="Resurser">
      {editing ? (
        <form className="wt-panel wt-form" onSubmit={save}>
          <h2>{editing === "new" ? "Ny resurs" : "Ändra resurs"}</h2>
          {editing === "new" && parent && <p className="wt-note">Ny del av <strong>{resourcePath(parent, org.resources)}</strong>. Ange ett eget namn, exempelvis Halvplan A eller Fjärdedelsplan A1. En delresurs skapas när du sparar.</p>}
          <label>Namn<input value={form.name} onChange={event => setForm({ ...form, name: event.target.value })} maxLength={120} required placeholder="T.ex. Plan 1, Minibuss, Kamera 2" /></label>
          <label>Typ
            <select value={form.category} onChange={event => setForm({ ...form, category: event.target.value as ResourceCategory })}>
              {categoryOrder.map(value => <option key={value} value={value}>{categoryLabels[value]}</option>)}
            </select>
          </label>
          <label>Del av en annan resurs (frivilligt)
            <select value={form.parent_resource_id} onChange={event => setForm({ ...form, parent_resource_id: event.target.value })}>
              <option value="">Fristående resurs</option>
              {org.resources.filter(item => resourceCanContain(item, editing === "new" ? null : editing, org.resources)).map(item => (
                <option key={item.id} value={item.id}>{resourcePath(item, org.resources)}{item.active ? "" : " (inaktiv)"}</option>
              ))}
            </select>
          </label>
          <p className="wt-small">Exempel: helplan → halvplan → fjärdedelsplan. En bokning spärrar överordnade och underordnade delar. Andra grenar kan bokas samtidigt. Delresurser följer även överordnade resursers dispositionsperioder och veckotider.</p>
          {form.category === "pitch" && !form.parent_resource_id && <fieldset><legend>Bokningsbar planindelning</legend>
            {org.resources.find(item => item.id === editing)?.pitch_layout ? <p>Helplan, två halvplaner, fyra fjärdedelar och ¾-plan är aktiverade. Delarnas namn kan ändras i resurslistan.</p> : org.resources.some(item => item.parent_resource_id === editing) ? <p>Planen har redan delresurser. Dessa kan väljas i bokningsformuläret.</p> : <>
              <label>Vad ska gå att boka?<select value={form.pitch_setup} onChange={event => setForm({...form,pitch_setup:event.target.value})}><option value="">Endast hela planen</option><option value="quarters">Helplan, halvplan, fjärdedelsplan och ¾-plan</option></select></label>
              {form.pitch_setup && <p className="wt-note">När du sparar skapas halvplan A och B, med fjärdedelarna A1, A2, B1 och B2. A och B ska vara två lika stora halvor. Varje halvplan delas i två lika stora delar. Namnge delarna så att bokaren känner igen dem på plats. Befintliga helplansbokningar spärrar alla delar.</p>}
            </>}
          </fieldset>}
          <details className="bk-resource-details" open={form.ownership_kind === "external" || !!form.available_from || !!form.available_until}><summary>Ägande och dispositionsperiod · {form.ownership_kind === "external" ? "Externt disponerad" : form.ownership_kind === "owned" ? "Egen resurs" : "Ej angivet"}</summary>
          <label>Ägande
            <select value={form.ownership_kind} onChange={event => setForm({ ...form, ownership_kind: event.target.value as ResourceOwnership })}>
              {form.ownership_kind === "unspecified" && <option value="unspecified">Ägande ej angivet</option>}
              <option value="owned">Egen resurs</option>
              <option value="external">Externt disponerad resurs</option>
            </select>
          </label>
          <label>{form.ownership_kind === "external" ? "Resursägare" : "Resursägare (frivilligt)"}
            <input value={form.owner_name} onChange={event => setForm({ ...form, owner_name: event.target.value })}
              required={form.ownership_kind === "external"} maxLength={160} placeholder="T.ex. kommunen eller fastighetsägaren" />
          </label>
          <fieldset>
            <legend>Dispositionsperiod {form.ownership_kind === "owned" ? "(frivilligt)" : ""}</legend>
            <p className="wt-small">Välj tills vidare om dispositionen saknar slutdatum. Hela från- och tilldagen ingår i resursens tidszon. Bokningar utanför perioden stoppas. Lämna båda datumen tomma för en egen resurs utan tidsbegränsning.</p>
            <label className="wt-check"><input type="checkbox" checked={form.indefinite} onChange={event => setForm({...form,indefinite:event.target.checked})} /><span>Tills vidare – inget slutdatum</span></label>
            <div className="bk-times">
              <label>Disponeras från<input type="date" value={form.available_from} onChange={event => setForm({ ...form, available_from: event.target.value })} required={form.ownership_kind === "external" || !!form.available_until} /></label>
              {!form.indefinite && <label>Disponeras till<input type="date" value={form.available_until} onChange={event => setForm({ ...form, available_until: event.target.value })} min={form.available_from || undefined} required={form.ownership_kind === "external" || !!form.available_from} /></label>}
            </div>
            <label>Resursens tidszon<input value={form.timezone} onChange={event => setForm({ ...form, timezone: event.target.value.trim() })} required maxLength={100} placeholder="Europe/Stockholm" /></label>
          </fieldset>
          </details>
          <details className="bk-resource-details"><summary>Bokningsbara tider och datumundantag</summary><p className="wt-small">{form.parent_resource_id ? "Överordnade resursers tidsbegränsningar gäller alltid. Här kan du begränsa den här delen ytterligare." : "Ange veckotider eller stäng enskilda datum vid behov."}</p><ResourceHours value={form.availability} onChange={availability => setForm({ ...form, availability })} /></details>
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
      {!editing && org.resources.length > 0 && <div className="wt-panel bk-resource-search">
        <div className="bk-panel-heading"><h2>Hitta och hantera resurser</h2><span className="wt-small">Aktiva: {org.resources.filter(resource => resource.active).length} · Inaktiva: {org.resources.filter(resource => !resource.active).length}</span></div>
        <div className="bk-resource-controls">
          <label>Sök bland resurser<input type="search" value={query} onChange={event => setQuery(event.target.value)} placeholder="Namn, plats, ägare eller överordnad resurs" /></label>
          <label>Resurstyp<select value={category} onChange={event => setCategory(event.target.value as ResourceCategory | "all")}><option value="all">Alla typer</option>{categoryOrder.map(value => <option key={value} value={value}>{categoryLabels[value]}</option>)}</select></label>
          <label>Resursstatus<select value={status} onChange={event => setStatus(event.target.value as ResourceStatusFilter)}><option value="all">Alla statusar</option><option value="active">Aktiva resurser</option><option value="inactive">Inaktiva resurser</option></select></label>
        </div>
        <div className="bk-panel-heading"><p className="wt-small" role="status">Matchande resurser: {matches} av {org.resources.length} · Resursgrupper: {groups.length}</p>{filtered && <button type="button" className="wt-link-button" onClick={() => { setQuery(""); setCategory("all"); setStatus("all"); }}>Rensa resursurval</button>}</div>
        <p className="wt-small">Delar visas tillsammans med sin huvudresurs. En halvplan kan ha egna mindre delar. Bokning av en resurs spärrar även dess överordnade och underordnade delar.</p>
        {filtered && <p className="wt-small">Hela resursgruppen visas för sammanhang, även delar som inte matchar urvalet. Aktiv status betyder att resursen är aktiverad; bokningsbara tider och övriga regler gäller fortfarande.</p>}
      </div>}
      {org.resources.length === 0 && !editing && <div className="wt-panel"><p>Inga resurser än. Lägg till den första med Ny resurs.</p></div>}
      {org.resources.length > 0 && groups.length === 0 && !editing && <p className="wt-note">Inga resurser matchar urvalet. Ändra sökningen eller rensa resursurvalet.</p>}
      {!editing && groups.map(group => (
        <section key={group.root.id} className="bk-group bk-resource-family" aria-label={`${group.root.name} med delar`}>
          <h2>{group.root.name}</h2>
          {group.items.length > 1 && <p className="wt-small">Huvudresurs med {group.items.length - 1} {group.items.length === 2 ? "delresurs" : "delresurser"}{filtered ? ` · Träffar: ${group.matchingIds.length}` : ""}</p>}
          <ul className="bk-resource-list">
            {group.items.map(({ resource, depth }) => (
              <li key={resource.id} data-inactive={!resource.active} data-resource-match={filtered && group.matchingIds.includes(resource.id)} style={{ paddingInlineStart: `${12 + Math.min(depth, 5) * 18}px` }}>
                <div>
                  <strong>{depth > 0 ? "↳ " : ""}{resource.name}</strong>
                  {filtered && <small className="bk-resource-context">{group.matchingIds.includes(resource.id) ? "Matchar urvalet" : "Relaterad resurs · visas för sammanhang"}</small>}
                  <span>{categoryLabels[resource.category]}{depth > 0 ? ` · Del av ${org.resources.find(item => item.id === resource.parent_resource_id)?.name ?? "annan resurs"}` : ""}</span>
                  <span>{[resource.location,resource.active ? "Aktiv" : "Inaktiv",resource.ownership_kind === "external" ? "Externt disponerad" : null,resource.requires_approval ? "Kräver godkännande" : "Bokas direkt"].filter(Boolean).join(" · ")}</span>
                  <details className="bk-resource-meta"><summary>Ägande och bokningsvillkor</summary>
                    <p>{[resource.ownership_kind === "external" ? `Extern · ${resource.owner_name || "Ägare ej angiven"}` : resource.ownership_kind === "owned" ? "Egen resurs" : "Ägande ej angivet",resource.available_from ? `Disponeras ${resource.available_from} – ${resource.available_until || "tills vidare"} (${resource.timezone})` : "Ingen egen dispositionsperiod angiven",resource.availability?.mode === "weekly" ? "Särskilda veckotider" : "Inga egna veckotider angivna",resource.availability?.exceptions.length ? `${resource.availability.exceptions.length} datumundantag` : null,resource.capacity ? `${resource.capacity} platser` : null].filter(Boolean).join(" · ")}</p>
                    {resource.parent_resource_id && <p>Överordnade resursers dispositionsperioder och bokningsbara tider gäller också för den här delen.</p>}
                    {!resource.active && <p>Resursen är inaktiverad och kan inte väljas för nya bokningar.</p>}
                  </details>
                </div>
                <div className="bk-resource-actions"><button type="button" className="wt-button secondary small" aria-label={`Ändra ${resourcePath(resource, org.resources)}`} onClick={() => edit(resource)}>Ändra</button>
                {resource.active && <button type="button" className="wt-button secondary small" aria-label={`Lägg till del av ${resourcePath(resource, org.resources)}`} onClick={() => edit(null, resource)}>+ Lägg till del</button>}</div>
              </li>
            ))}
          </ul>
        </section>
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
