"use client";

import { useCallback, useEffect, useState } from "react";
import { validHexColor } from "../../lib/admin";
import { call, NoticeBar, Panel, useAdminAction, type AdminEnv } from "./admin-ui";

const badgeTypes = ["image/jpeg", "image/png", "image/webp"];
const maxBadgeBytes = 1_048_576;

export function AdminBrand({ env }: { env: AdminEnv }) {
  return <>
    <ClubColors env={env} />
    <ClubBadge env={env} />
  </>;
}

function ClubColors({ env }: { env: AdminEnv }) {
  const { rpc, scope } = env;
  const [primary, setPrimary] = useState("");
  const [accent, setAccent] = useState("");
  const [loaded, setLoaded] = useState(false);
  const { busy, notice, setNotice, run } = useAdminAction();

  useEffect(() => {
    call(rpc, "get_club_colors", { target_club_id: scope.clubId }).then(data => {
      const colors = (data ?? {}) as { primary?: string; accent?: string };
      setPrimary(colors.primary ?? ""); setAccent(colors.accent ?? ""); setLoaded(true);
    }).catch(() => setNotice({ kind: "error", text: "Färgerna kunde inte hämtas." }));
  }, [rpc, scope.clubId, setNotice]);

  async function save(reset: boolean) {
    if (!reset && ((primary && !validHexColor(primary)) || (accent && !validHexColor(accent)))) {
      setNotice({ kind: "error", text: "Ange färgerna som #rrggbb, t.ex. #00843d." });
      return;
    }
    const ok = await run(() => call(rpc, "set_club_colors", {
      target_club_id: scope.clubId, new_primary: reset ? null : primary || null, new_accent: reset ? null : accent || null,
    }).then(() => undefined), reset ? "Standardfärgerna används igen." : "Färgerna är sparade. Sidan uppdateras inom en minut.");
    if (ok && reset) { setPrimary(""); setAccent(""); }
  }

  return <Panel title="Klubbens färger" lead="Huvudfärgen används i sidhuvud och mörka ytor, accentfärgen för markeringar.">
    {!loaded && !notice && <p className="ad-muted">Hämtar…</p>}
    {loaded && <form className="ad-form" onSubmit={event => { event.preventDefault(); void save(false); }}>
      <div className="ad-color-row">
        <ColorField label="Huvudfärg" value={primary} onChange={setPrimary} fallback="#0b1f3a" />
        <ColorField label="Accentfärg" value={accent} onChange={setAccent} fallback="#ffd100" />
      </div>
      <div className="ad-swatch" style={{ background: validHexColor(primary) ? primary : "#0b1f3a" }}>
        <span style={{ background: validHexColor(accent) ? accent : "#ffd100" }} />
        <strong>{scope.clubName}</strong>
      </div>
      <NoticeBar notice={notice} />
      <div className="ad-actions">
        <button type="button" className="ad-button ghost" disabled={busy} onClick={() => void save(true)}>Återställ</button>
        <button className="ad-button" disabled={busy}>Spara färger</button>
      </div>
    </form>}
  </Panel>;
}

function ColorField({ label, value, onChange, fallback }: { label: string; value: string; onChange: (value: string) => void; fallback: string }) {
  return <label>{label}
    <span className="ad-color">
      <input type="color" aria-label={`${label}, väljare`} value={validHexColor(value) ? value.toLowerCase() : fallback} onChange={event => onChange(event.target.value)} />
      <input value={value} placeholder={fallback} maxLength={7} onChange={event => onChange(event.target.value.trim())} />
    </span>
  </label>;
}

function ClubBadge({ env }: { env: AdminEnv }) {
  const { rpc, client, scope, selfService } = env;
  const [hasBadge, setHasBadge] = useState(false);
  const [url, setUrl] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const { busy, notice, setNotice, run } = useAdminAction();

  // The site's CSP only allows same-origin images, so the preview uses the
  // club's public badge address (published clubs) rather than a storage URL.
  const load = useCallback(async () => {
    setLoading(true);
    try {
      const data = await call(rpc, "authorize_club_badge", { target_club_id: scope.clubId }) as { bucket_id?: string; object_key?: string } | null;
      const exists = data?.bucket_id === "club-badges" && typeof data.object_key === "string";
      setHasBadge(exists);
      let publicPath: string | null = null;
      if (exists && selfService.club.mode === "published") {
        const response = await fetch(`/api/public/v1/clubs/${encodeURIComponent(selfService.club.slug)}`, { cache: "no-store" });
        const page = response.ok ? await response.json() as { profile_media_path?: string | null } : null;
        publicPath = page?.profile_media_path?.startsWith("/media/public/") ? page.profile_media_path : null;
      }
      setUrl(publicPath);
    } catch { setUrl(null); } finally { setLoading(false); }
  }, [rpc, scope.clubId, selfService.club.mode, selfService.club.slug]);
  useEffect(() => { void load(); }, [load]);

  async function upload(file: File) {
    if (!badgeTypes.includes(file.type)) { setNotice({ kind: "error", text: "Välj en JPEG-, PNG- eller WebP-bild." }); return; }
    if (file.size > maxBadgeBytes) { setNotice({ kind: "error", text: "Bilden får vara högst 1 MB." }); return; }
    const ok = await run(async () => {
      const staged = await call(rpc, "stage_club_badge", { target_club_id: scope.clubId, target_mime_type: file.type, target_size_bytes: file.size }) as { bucket_id?: string; object_key?: string; badge_id?: string };
      if (staged?.bucket_id !== "club-badges" || !staged.object_key || !staged.badge_id) throw new Error("invalid_stage");
      const { error } = await client.storage.from("club-badges").upload(staged.object_key, file, { contentType: file.type, upsert: false });
      if (error) throw error;
      await call(rpc, "set_club_badge", { target_club_id: scope.clubId, badge_action: "replace", staged_badge_id: staged.badge_id });
    }, "Klubbmärket är uppdaterat.", "Klubbmärket kunde inte laddas upp. Försök igen.");
    if (ok) await load();
  }

  async function remove() {
    const ok = await run(() => call(rpc, "set_club_badge", { target_club_id: scope.clubId, badge_action: "remove", staged_badge_id: null }).then(() => undefined), "Klubbmärket är borttaget.");
    if (ok) await load();
  }

  return <Panel title="Klubbmärke" lead="Visas på klubbens och lagens publika sidor och på medlemskorten. JPEG, PNG eller WebP, högst 1 MB.">
    <div className="ad-badge">
      {loading ? <p className="ad-muted">Hämtar…</p>
        : url ? <img src={url} alt={`${scope.clubName}s klubbmärke`} />
        : hasBadge ? <p className="ad-empty">Ett klubbmärke är uppladdat. Det visas här när klubbsidan är publicerad.</p>
        : <p className="ad-empty">Inget klubbmärke uppladdat.</p>}
    </div>
    <NoticeBar notice={notice} />
    <div className="ad-actions">
      {hasBadge && <button className="ad-button ghost" disabled={busy} onClick={() => void remove()}>Ta bort</button>}
      <label className={`ad-button${busy ? " disabled" : ""}`}>{hasBadge ? "Byt klubbmärke" : "Ladda upp klubbmärke"}
        <input className="ad-file" type="file" accept={badgeTypes.join(",")} disabled={busy} onChange={event => { const file = event.target.files?.[0]; event.target.value = ""; if (file) void upload(file); }} />
      </label>
    </div>
  </Panel>;
}
