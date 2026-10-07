"use client";

import { useState } from "react";
import { newIdempotencyKey, publicationFields, publicationModeLabel, requestStatusLabel, validSlug, type SelfServiceItem } from "../../lib/admin";
import { call, NoticeBar, Panel, useAdminAction, type AdminEnv } from "./admin-ui";

type Editing = { type: "club" | "team"; item: SelfServiceItem } | null;

export function AdminPages({ env }: { env: AdminEnv }) {
  const { rpc, scope, selfService, reload } = env;
  const club = selfService.club;
  const clubPublished = club.mode === "published";
  const [editing, setEditing] = useState<Editing>(null);
  const [requestFor, setRequestFor] = useState<SelfServiceItem | null>(null);
  const [requestMessage, setRequestMessage] = useState("");
  const { busy, notice, setNotice, run } = useAdminAction();
  const pending = (selfService.requests ?? []).filter(request => request.status === "pending");

  async function request(team: SelfServiceItem) {
    const ok = await run(() => call(rpc, "request_team_publication", { club_id: scope.clubId, team_id: team.id, message: requestMessage.trim() }).then(() => undefined),
      "Ansökan är skickad till klubben och väntar på beslut.");
    if (ok) { setRequestFor(null); setRequestMessage(""); await reload(); }
  }

  async function decide(requestId: string, approve: boolean) {
    const ok = await run(() => call(rpc, "decide_team_publication", { request_id: requestId, approve, note: "" }).then(() => undefined),
      approve ? "Ansökan är godkänd. Välj lagets synlighet för att publicera sidan." : "Ansökan är avslagen.");
    if (ok) await reload();
  }

  if (editing) return <PageSettings env={env} editing={editing} clubPublished={clubPublished} onDone={async saved => { setEditing(null); if (saved) { setNotice({ kind: "success", text: "Ändringen är sparad." }); await reload(); } }} />;

  return <>
    <Panel title="Klubbsidan" lead={`${publicationModeLabel[club.mode] ?? club.mode} · /${club.slug}`}
      actions={scope.canManageClub ? <button className="ad-button" onClick={() => setEditing({ type: "club", item: club })}>Ändra</button> : undefined}>
      {!clubPublished && <p className="ad-muted">Klubbsidan visas inte för besökare förrän den är publicerad. Lagsidor och nyheter kräver en publicerad klubbsida.</p>}
      {club.locality && club.fields?.includes("locality") && <p>Ort: {club.locality}</p>}
      {club.description && club.fields?.includes("description") && <p>{club.description}</p>}
    </Panel>
    <NoticeBar notice={notice} />
    {scope.canManageClub && pending.length > 0 && <Panel title="Ansökningar om lagsida">
      <ul className="ad-list">{pending.map(item => <li key={item.id}>
        <div className="ad-list-main"><strong>{item.team_name}</strong>{item.message && <small>{item.message}</small>}</div>
        <div className="ad-list-actions"><button className="ad-link" disabled={busy} onClick={() => void decide(item.id, true)}>Godkänn</button><button className="ad-link" disabled={busy} onClick={() => void decide(item.id, false)}>Avslå</button></div>
      </li>)}</ul>
    </Panel>}
    <Panel title="Lagsidor" lead="Ett lag syns publikt när klubben har publicerat lagets sida.">
      {!(selfService.teams ?? []).length && <p className="ad-empty">Inga lag att visa.</p>}
      <ul className="ad-list">{(selfService.teams ?? []).map(team => {
        const hiddenByClub = team.mode === "published" && !clubPublished;
        const canRequest = team.can_request && !scope.canManageClub && team.request_status !== "pending" && team.request_status !== "approved" && team.mode !== "published";
        return <li key={team.id}>
          <div className="ad-list-main">
            <strong>{team.name}</strong>
            <span className={`ad-state ${team.mode}`}>{publicationModeLabel[team.mode] ?? team.mode}</span>
            <small>{hiddenByClub ? "Dold – klubbsidan är inte publicerad" : `/${club.slug}/${team.slug}`}{team.request_status ? ` · Ansökan: ${requestStatusLabel[team.request_status] ?? team.request_status}` : ""}</small>
          </div>
          <div className="ad-list-actions">
            {scope.canManageClub && <button className="ad-link" onClick={() => setEditing({ type: "team", item: team })}>Ändra</button>}
            {canRequest && <button className="ad-link" onClick={() => { setRequestFor(team); setRequestMessage(""); }}>Ansök om lagsida</button>}
          </div>
          {requestFor?.id === team.id && <form className="ad-inline" onSubmit={event => { event.preventDefault(); void request(team); }}>
            <label>Meddelande till klubben (valfritt)<textarea rows={2} maxLength={1000} value={requestMessage} onChange={event => setRequestMessage(event.target.value)} /></label>
            <button className="ad-button" disabled={busy}>Skicka ansökan</button><button type="button" className="ad-link" onClick={() => setRequestFor(null)}>Avbryt</button>
          </form>}
        </li>;
      })}</ul>
    </Panel>
  </>;
}

function PageSettings({ env, editing, clubPublished, onDone }: { env: AdminEnv; editing: NonNullable<Editing>; clubPublished: boolean; onDone: (saved: boolean) => void }) {
  const { rpc, scope } = env;
  const { type, item } = editing;
  const fields = item.fields ?? [];
  const initialMode = type === "team" && (item.mode === "listed" || !clubPublished) ? "private" : item.mode;
  const [mode, setMode] = useState(initialMode);
  const [slug, setSlug] = useState(item.slug);
  const [locality, setLocality] = useState(item.locality ?? "");
  const [description, setDescription] = useState(item.description ?? "");
  const [ageClass, setAgeClass] = useState(item.age_class ?? "");
  const [showLocality, setShowLocality] = useState(fields.includes("locality"));
  const [showDescription, setShowDescription] = useState(fields.includes("description"));
  const [showAgeClass, setShowAgeClass] = useState(fields.includes("age_class"));
  const [confirmed, setConfirmed] = useState(false);
  const { busy, notice, setNotice, run } = useAdminAction();
  const slugOk = validSlug(slug.trim().toLowerCase(), 2, 80);

  async function save(event: React.FormEvent) {
    event.preventDefault();
    if (!slugOk) { setNotice({ kind: "error", text: "Använd 2–80 tecken: a–z, 0–9 och bindestreck." }); return; }
    if (mode !== "private" && !confirmed) { setNotice({ kind: "error", text: "Bekräfta att uppgifterna får publiceras." }); return; }
    const ok = await run(() => call(rpc, "configure_publication_v2", {
      club_id: scope.clubId, aggregate_type: type, aggregate_id: item.id, mode, slug: slug.trim().toLowerCase(),
      fields: publicationFields(type, mode, { locality, description, ageClass, showLocality, showDescription, showAgeClass }),
      locality: locality.trim(), description: description.trim(), age_class: ageClass.trim(),
      policy_version: "pub02-self-service-v1", confirmation_expires_at: new Date(Date.now() + 365 * 86_400_000).toISOString(),
      expected_revision: item.revision ?? 0, idempotency_key: newIdempotencyKey(),
    }).then(() => undefined), "Ändringen är sparad.");
    if (ok) onDone(true);
  }

  return <Panel title={type === "club" ? "Klubbens publika sida" : `Lagsida · ${item.name}`}>
    <form className="ad-form" onSubmit={save}>
      <label>Synlighet<select value={mode} onChange={event => setMode(event.target.value)}>
        <option value="private">Privat</option>
        {type === "club" && <option value="listed">Endast i katalogen</option>}
        {(type === "club" || clubPublished) && <option value="published">Publicerad</option>}
      </select></label>
      {type === "club" && <p className="ad-muted">{mode === "published" ? "Klubbsidan och valda uppgifter visas för alla besökare." : mode === "listed" ? "Klubben syns i sökningen men har ingen egen sida." : "Klubben syns inte publikt."}</p>}
      {type === "team" && !clubPublished && <p className="ad-muted">Lagsidan kan publiceras först när klubbsidan är publicerad.</p>}
      <label>Webbadress<input value={slug} maxLength={80} onChange={event => setSlug(event.target.value.toLowerCase())} /><small>{slugOk ? (type === "club" ? `/${slug}` : `/${env.selfService.club.slug}/${slug}`) : "2–80 tecken: a–z, 0–9 och bindestreck."}</small></label>
      {type === "club" ? <>
        <label>Ort<input value={locality} maxLength={120} onChange={event => setLocality(event.target.value)} /></label>
        <label className="ad-check"><input type="checkbox" checked={showLocality} onChange={event => setShowLocality(event.target.checked)} />Visa ort publikt</label>
        <label>Presentation<textarea rows={4} maxLength={1000} value={description} onChange={event => setDescription(event.target.value)} /></label>
        <label className="ad-check"><input type="checkbox" checked={showDescription} onChange={event => setShowDescription(event.target.checked)} />Visa presentation publikt</label>
      </> : <>
        <label>Åldersklass<input value={ageClass} maxLength={60} onChange={event => setAgeClass(event.target.value)} /></label>
        <label className="ad-check"><input type="checkbox" checked={showAgeClass} onChange={event => setShowAgeClass(event.target.checked)} />Visa åldersklass publikt</label>
      </>}
      {mode !== "private" && <label className="ad-check"><input type="checkbox" checked={confirmed} onChange={event => setConfirmed(event.target.checked)} />Jag bekräftar att namn och valda uppgifter får publiceras på webben. Bekräftelsen gäller i högst ett år.</label>}
      <NoticeBar notice={notice} />
      <div className="ad-actions">
        <button type="button" className="ad-button ghost" disabled={busy} onClick={() => onDone(false)}>Avbryt</button>
        <button className="ad-button" disabled={busy}>Spara</button>
      </div>
    </form>
  </Panel>;
}
