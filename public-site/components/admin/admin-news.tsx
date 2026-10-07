"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { articleStateLabel, blocksFromText, newIdempotencyKey, suggestSlug, textFromBlocks, validSlug, type ArticleBlock } from "../../lib/admin";
import { heroStateLabel, imageErrorMessage, prepareImage, startImageProcessing, uploadNewsImage, type PreparedImage } from "../../lib/admin-image";
import { call, NoticeBar, Panel, useAdminAction, type AdminEnv } from "./admin-ui";

type Article = {
  id: string; slug: string; title: string; summary?: string | null; body_blocks?: ArticleBlock[];
  state: string; publish_at?: string | null; published_at?: string | null; author_label?: string | null;
  publish_to_club: boolean; teams?: string[]; revision: number;
  media_status?: string; hero_asset_id?: string | null; hero_alt?: string | null; hero_path?: string | null;
};

type Draft = {
  id?: string; revision: number; title: string; slug: string; slugTouched: boolean; summary: string; body: string; author: string; publishToClub: boolean; teams: string[];
  /** The saved hero, if any. */
  heroAssetId: string | null; heroPath: string | null; heroState: string;
  /** A newly chosen image, prepared in the browser. */
  newImage: PreparedImage | null; removeImage: boolean; alt: string; savedAlt: string;
};

const emptyDraft: Draft = { revision: 0, title: "", slug: "", slugTouched: false, summary: "", body: "", author: "", publishToClub: true, teams: [], heroAssetId: null, heroPath: null, heroState: "none", newImage: null, removeImage: false, alt: "", savedAlt: "" };

function toDraft(article: Article): Draft {
  return { id: article.id, revision: article.revision, title: article.title, slug: article.slug, slugTouched: true, summary: article.summary ?? "", body: textFromBlocks(article.body_blocks), author: article.author_label ?? "", publishToClub: article.publish_to_club, teams: article.teams ?? [],
    heroAssetId: article.hero_asset_id ?? null, heroPath: article.hero_path ?? null, heroState: article.media_status ?? "none", newImage: null, removeImage: false, alt: article.hero_alt ?? "", savedAlt: article.hero_alt ?? "" };
}

/** The browser-prepared image, drawn on a canvas: the site's CSP blocks blob: images. */
function ImagePreview({ image }: { image: PreparedImage }) {
  const canvas = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const element = canvas.current;
    if (!element) return;
    element.width = image.width;
    element.height = image.height;
    element.getContext("2d")?.drawImage(image.bitmap, 0, 0);
  }, [image]);
  return <canvas ref={canvas} className="ad-hero-preview" role="img" aria-label="Vald bild" />;
}

const dateTime = (value?: string | null) => value ? new Intl.DateTimeFormat("sv-SE", { dateStyle: "medium", timeStyle: "short", timeZone: "Europe/Stockholm" }).format(new Date(value)) : "";

export function AdminNews({ env, clubSlug }: { env: AdminEnv; clubSlug: string }) {
  const { rpc, client, scope, selfService } = env;
  const clubPublished = selfService.club.mode === "published";
  const [articles, setArticles] = useState<Article[] | null>(null);
  const [loadError, setLoadError] = useState("");
  const [draft, setDraft] = useState<Draft | null>(null);
  const [scheduleFor, setScheduleFor] = useState<Article | null>(null);
  const [scheduleAt, setScheduleAt] = useState("");
  const { busy, notice, setNotice, run } = useAdminAction();

  const load = useCallback(async () => {
    setLoadError("");
    try { setArticles(await call(rpc, "list_editorial_articles", { club_id: scope.clubId }) as Article[]); }
    catch { setLoadError("Nyheterna kunde inte hämtas. Försök igen."); }
  }, [rpc, scope.clubId]);
  useEffect(() => { void load(); }, [load]);

  async function save(publish: boolean) {
    if (!draft) return;
    const slug = draft.slug.trim();
    if (!draft.title.trim()) { setNotice({ kind: "error", text: "Skriv en rubrik." }); return; }
    if (!validSlug(slug)) { setNotice({ kind: "error", text: "Webbadressen ska vara 2–100 tecken: a–z, 0–9 och bindestreck." }); return; }
    if (!draft.body.trim()) { setNotice({ kind: "error", text: "Skriv själva nyheten." }); return; }
    if (!draft.publishToClub && !draft.teams.length) { setNotice({ kind: "error", text: "Välj klubbsidan eller minst ett lag." }); return; }
    if (publish && !clubPublished) { setNotice({ kind: "error", text: "Klubbsidan måste vara publicerad innan nyheter kan publiceras. Gör det under Sidan." }); return; }
    const ok = await run(async () => {
      const saved = await call(rpc, "save_editorial_article", {
        club_id: scope.clubId, article_id: draft.id ?? null, slug, title: draft.title.trim(),
        summary: draft.summary.trim() || null, blocks: blocksFromText(draft.body),
        author_label: draft.author.trim() || null, publish_to_club: draft.publishToClub,
        team_ids: draft.teams, expected_revision: draft.revision, idempotency_key: newIdempotencyKey(),
      }) as { article_id?: string; revision?: number } | null;
      if (!saved?.article_id || typeof saved.revision !== "number") throw new Error("saved_article_missing");
      let revision = saved.revision;
      // The image is set after the text, on the article's new revision.
      const altChanged = draft.alt.trim() !== draft.savedAlt.trim();
      if (draft.newImage || draft.removeImage || (draft.heroAssetId && altChanged)) {
        const assetId = draft.newImage ? await uploadNewsImage(client, rpc, scope.clubId, draft.newImage.blob)
          : draft.removeImage ? null : draft.heroAssetId;
        const hero = await call(rpc, "set_editorial_article_hero", {
          article_id: saved.article_id, asset_id: assetId, alt: assetId ? draft.alt.trim() || null : null,
          expected_revision: revision, idempotency_key: newIdempotencyKey(),
        }) as { revision?: number };
        revision = hero.revision ?? revision;
        if (draft.newImage) await startImageProcessing(client);
      }
      if (publish) {
        await call(rpc, "transition_editorial_article", { article_id: saved.article_id, state: "published", publish_at: null, expected_revision: revision, idempotency_key: newIdempotencyKey() });
      }
    }, publish ? "Nyheten är publicerad." : "Nyheten är sparad som utkast.");
    if (ok) { setDraft(null); await load(); }
  }

  async function chooseImage(file: File | undefined) {
    if (!file || !draft) return;
    setNotice(null);
    try {
      const image = await prepareImage(file);
      setDraft(current => current ? { ...current, newImage: image, removeImage: false } : current);
    } catch (error) {
      setNotice({ kind: "error", text: imageErrorMessage(error) });
    }
  }

  async function transition(article: Article, state: string, publishAt?: string) {
    if ((state === "published" || state === "scheduled") && !clubPublished) {
      setNotice({ kind: "error", text: "Klubbsidan måste vara publicerad innan nyheter kan publiceras. Gör det under Sidan." });
      return;
    }
    const ok = await run(() => call(rpc, "transition_editorial_article", {
      article_id: article.id, state, publish_at: publishAt ?? null, expected_revision: article.revision, idempotency_key: newIdempotencyKey(),
    }).then(() => undefined), state === "unpublished" ? "Nyheten är avpublicerad." : state === "scheduled" ? "Nyheten är schemalagd." : "Nyheten är publicerad.");
    if (ok) { setScheduleFor(null); await load(); }
  }

  async function edit(article: Article) {
    const full = await rpc("get_editorial_article", { article_id: article.id });
    setNotice(null);
    setDraft(toDraft(!full.error && full.data ? { ...article, ...(full.data as Article) } : article));
  }

  if (draft) {
    const update = (patch: Partial<Draft>) => setDraft(current => current ? { ...current, ...patch } : current);
    return <Panel title={draft.id ? "Redigera nyhet" : "Ny nyhet"} lead="Nyheten visas på de sidor du väljer när den publiceras.">
      <form className="ad-form" onSubmit={event => { event.preventDefault(); void save(false); }}>
        <label>Rubrik<input value={draft.title} maxLength={160} required onChange={event => update({ title: event.target.value, ...(draft.slugTouched ? {} : { slug: suggestSlug(event.target.value) }) })} /></label>
        <label>Webbadress<input value={draft.slug} maxLength={100} onChange={event => update({ slug: event.target.value.toLowerCase(), slugTouched: true })} /><small>/{clubSlug}/nyheter/{draft.slug || "…"}</small></label>
        <label>Ingress (valfri)<textarea rows={2} maxLength={500} value={draft.summary} onChange={event => update({ summary: event.target.value })} /></label>
        <label>Text<textarea rows={10} value={draft.body} onChange={event => update({ body: event.target.value })} /><small>Tom rad mellan stycken.</small></label>
        <fieldset className="ad-hero"><legend>Bild (valfri)</legend>
          {draft.newImage ? <ImagePreview image={draft.newImage} />
            : !draft.removeImage && draft.heroPath ? <img className="ad-hero-preview" src={draft.heroPath} alt={draft.alt} />
            : !draft.removeImage && draft.heroAssetId ? <p className="ad-muted">{heroStateLabel[draft.heroState] ?? "Bild vald"}.</p>
            : <p className="ad-muted">Ingen bild vald. Bilden visas överst i nyheten och på nyhetskortet.</p>}
          {(draft.newImage || (draft.heroAssetId && !draft.removeImage)) && <label>Bildbeskrivning<input value={draft.alt} maxLength={200} placeholder="T.ex. Laget firar efter matchen" onChange={event => update({ alt: event.target.value })} /><small>Läses upp för den som inte kan se bilden.</small></label>}
          <div className="ad-actions">
            {(draft.newImage || (draft.heroAssetId && !draft.removeImage)) && <button type="button" className="ad-button ghost" disabled={busy} onClick={() => update({ newImage: null, removeImage: Boolean(draft.heroAssetId) })}>Ta bort bilden</button>}
            <label className={`ad-button ghost${busy ? " disabled" : ""}`}>{draft.newImage || (draft.heroAssetId && !draft.removeImage) ? "Byt bild" : "Välj bild"}
              <input className="ad-file" type="file" accept="image/*" disabled={busy} onChange={event => { const file = event.target.files?.[0]; event.target.value = ""; void chooseImage(file); }} />
            </label>
          </div>
          <small>Bilden skalas ner och platsuppgifter och annan metadata tas bort innan den publiceras.</small>
        </fieldset>
        <label>Skribent (valfri)<input value={draft.author} maxLength={120} onChange={event => update({ author: event.target.value })} /></label>
        <fieldset><legend>Visas på</legend>
          <label className="ad-check"><input type="checkbox" checked={draft.publishToClub} onChange={event => update({ publishToClub: event.target.checked })} />Klubbens sida</label>
          {(selfService.teams ?? []).map(team => <label key={team.id} className="ad-check"><input type="checkbox" checked={draft.teams.includes(team.id)} onChange={event => update({ teams: event.target.checked ? [...draft.teams, team.id] : draft.teams.filter(id => id !== team.id) })} />{team.name}{team.mode !== "published" ? " (lagsidan är inte publicerad)" : ""}</label>)}
        </fieldset>
        <details className="ad-preview"><summary>Förhandsgranska</summary>
          <article><h3>{draft.title || "Rubrik"}</h3>{draft.summary && <p className="ad-lead">{draft.summary}</p>}{blocksFromText(draft.body).map((block, index) => <p key={index}>{block.text}</p>)}{draft.author && <p className="ad-muted">Av {draft.author}</p>}</article>
        </details>
        <NoticeBar notice={notice} />
        <div className="ad-actions">
          <button type="button" className="ad-button ghost" disabled={busy} onClick={() => { setDraft(null); setNotice(null); }}>Avbryt</button>
          <button type="submit" className="ad-button ghost" disabled={busy}>Spara utkast</button>
          {(!draft.id || articles?.find(item => item.id === draft.id)?.state !== "published") && <button type="button" className="ad-button" disabled={busy} onClick={() => void save(true)}>Spara och publicera</button>}
        </div>
      </form>
    </Panel>;
  }

  return <Panel title="Nyheter" lead={clubPublished ? "Skriv, publicera och avpublicera klubbens nyheter." : "Klubbsidan är inte publicerad ännu. Du kan skriva utkast, men publicera sidan under Sidan innan nyheter visas."}
    actions={<button className="ad-button" onClick={() => { setNotice(null); setDraft({ ...emptyDraft }); }}>Ny nyhet</button>}>
    <NoticeBar notice={notice} />
    {loadError && <p className="ad-notice error">{loadError} <button className="ad-link" onClick={() => void load()}>Försök igen</button></p>}
    {articles === null && !loadError && <p className="ad-muted">Hämtar nyheter…</p>}
    {articles?.length === 0 && <p className="ad-empty">Inga nyheter ännu.</p>}
    <ul className="ad-list">
      {articles?.map(article => <li key={article.id}>
        <div className="ad-list-main">
          <strong>{article.title}</strong>
          <span className={`ad-state ${article.state}`}>{articleStateLabel[article.state] ?? article.state}</span>
          {article.media_status && article.media_status !== "none" && <span className={`ad-state ${article.media_status === "ready" ? "published" : article.media_status === "pending" ? "scheduled" : "unpublished"}`}>{heroStateLabel[article.media_status] ?? article.media_status}</span>}
          <small>{article.state === "scheduled" ? `Publiceras ${dateTime(article.publish_at)}` : article.published_at ? `Publicerad ${dateTime(article.published_at)}` : `/${article.slug}`}</small>
        </div>
        <div className="ad-list-actions">
          {article.state === "published" && <a className="ad-link" href={`/${clubSlug}/nyheter/${article.slug}`} target="_blank" rel="noreferrer">Visa</a>}
          {article.state !== "published" && <button className="ad-link" disabled={busy} onClick={() => void edit(article)}>Redigera</button>}
          {article.state !== "published" && <button className="ad-link" disabled={busy} onClick={() => void transition(article, "published")}>Publicera</button>}
          {article.state !== "published" && <button className="ad-link" disabled={busy} onClick={() => { setScheduleFor(article); setScheduleAt(""); }}>Schemalägg</button>}
          {article.state === "published" && <button className="ad-link" disabled={busy} onClick={() => void transition(article, "unpublished")}>Avpublicera</button>}
        </div>
        {scheduleFor?.id === article.id && <form className="ad-inline" onSubmit={event => { event.preventDefault(); const at = new Date(scheduleAt); if (!scheduleAt || at.getTime() <= Date.now()) { setNotice({ kind: "error", text: "Välj en tidpunkt i framtiden." }); return; } void transition(article, "scheduled", at.toISOString()); }}>
          <label>Publicera<input type="datetime-local" value={scheduleAt} onChange={event => setScheduleAt(event.target.value)} required /></label>
          <button className="ad-button" disabled={busy}>Schemalägg</button><button type="button" className="ad-link" onClick={() => setScheduleFor(null)}>Avbryt</button>
        </form>}
      </li>)}
    </ul>
  </Panel>;
}
