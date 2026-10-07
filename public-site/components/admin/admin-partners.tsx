"use client";

import { useCallback, useEffect, useState } from "react";
import { newIdempotencyKey, validPartnerUrl } from "../../lib/admin";
import { call, NoticeBar, Panel, useAdminAction, type AdminEnv } from "./admin-ui";

type Partner = { id: string; name: string; website_url?: string | null; state: string; sort_order: number; revision: number };
type Draft = { id?: string; name: string; website: string; state: string; order: number; revision: number };

const partnerStateLabel: Record<string, string> = { draft: "Utkast", published: "Publicerad", unpublished: "Avpublicerad" };

export function AdminPartners({ env }: { env: AdminEnv }) {
  const { rpc, scope } = env;
  const [partners, setPartners] = useState<Partner[] | null>(null);
  const [canManage, setCanManage] = useState(false);
  const [loadError, setLoadError] = useState(false);
  const [draft, setDraft] = useState<Draft | null>(null);
  const { busy, notice, setNotice, run } = useAdminAction();

  const load = useCallback(async () => {
    setLoadError(false);
    try {
      const data = await call(rpc, "get_publication_management", { club_id: scope.clubId }) as { partners?: Partner[]; can_manage_partners?: boolean };
      setPartners([...(data.partners ?? [])].sort((a, b) => a.sort_order - b.sort_order || a.name.localeCompare(b.name, "sv")));
      setCanManage(data.can_manage_partners === true);
    } catch { setLoadError(true); }
  }, [rpc, scope.clubId]);
  useEffect(() => { void load(); }, [load]);

  async function save(event: React.FormEvent) {
    event.preventDefault();
    if (!draft) return;
    if (!draft.name.trim()) { setNotice({ kind: "error", text: "Ange partnerns namn." }); return; }
    if (!validPartnerUrl(draft.website)) { setNotice({ kind: "error", text: "Webbadressen ska börja med https://." }); return; }
    const ok = await run(() => call(rpc, "save_public_partner", {
      club_id: scope.clubId, partner_id: draft.id ?? null, name: draft.name.trim(), website_url: draft.website.trim() || null,
      logo_asset_id: null, state: draft.state, sort_order: draft.order, expected_revision: draft.revision, idempotency_key: newIdempotencyKey(),
    }).then(() => undefined), "Partnern är sparad.");
    if (ok) { setDraft(null); await load(); }
  }

  if (loadError) return <Panel title="Partners"><p className="ad-notice error">Partnerna kunde inte hämtas. <button className="ad-link" onClick={() => void load()}>Försök igen</button></p></Panel>;
  if (!partners) return <Panel title="Partners"><p className="ad-muted">Hämtar…</p></Panel>;

  if (draft) {
    const update = (patch: Partial<Draft>) => setDraft({ ...draft, ...patch });
    return <Panel title={draft.id ? "Redigera partner" : "Ny partner"}>
      <form className="ad-form" onSubmit={save}>
        <label>Namn<input value={draft.name} maxLength={120} required onChange={event => update({ name: event.target.value })} /></label>
        <label>Webbadress (valfri)<input type="url" placeholder="https://" value={draft.website} onChange={event => update({ website: event.target.value })} /></label>
        <label>Ordning<input type="number" min={0} max={1000} value={draft.order} onChange={event => update({ order: Number(event.target.value) || 0 })} /><small>Lägre nummer visas först.</small></label>
        <label>Status<select value={draft.state} onChange={event => update({ state: event.target.value })}>
          {Object.entries(partnerStateLabel).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
        </select></label>
        <NoticeBar notice={notice} />
        <div className="ad-actions">
          <button type="button" className="ad-button ghost" disabled={busy} onClick={() => { setDraft(null); setNotice(null); }}>Avbryt</button>
          <button className="ad-button" disabled={busy}>Spara</button>
        </div>
      </form>
    </Panel>;
  }

  return <Panel title="Partners" lead="Publicerade partners visas på klubbsidan."
    actions={canManage ? <button className="ad-button" onClick={() => { setNotice(null); setDraft({ name: "", website: "", state: "published", order: (partners.at(-1)?.sort_order ?? 0) + 1, revision: 0 }); }}>Ny partner</button> : undefined}>
    <NoticeBar notice={notice} />
    {!canManage && <p className="ad-muted">Du kan se partnerna men inte ändra dem.</p>}
    {!partners.length && <p className="ad-empty">Inga partners ännu.</p>}
    <ul className="ad-list">{partners.map(partner => <li key={partner.id}>
      <div className="ad-list-main">
        <strong>{partner.name}</strong>
        <span className={`ad-state ${partner.state}`}>{partnerStateLabel[partner.state] ?? partner.state}</span>
        {partner.website_url && <small>{partner.website_url}</small>}
      </div>
      {canManage && <div className="ad-list-actions"><button className="ad-link" onClick={() => { setNotice(null); setDraft({ id: partner.id, name: partner.name, website: partner.website_url ?? "", state: partner.state, order: partner.sort_order, revision: partner.revision }); }}>Redigera</button></div>}
    </li>)}</ul>
  </Panel>;
}
