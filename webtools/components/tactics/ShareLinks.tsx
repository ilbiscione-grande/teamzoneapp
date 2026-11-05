"use client";

// The links in the share dialog: to the whole project or the board in hand.
// Anyone with one watches and plays the boards without an account, always as
// last saved, until the link is revoked. Each link can be copied, sent
// through the phone's own sharing, by e-mail, text or WhatsApp, or shown as
// a QR code.
import { useCallback, useEffect, useState } from "react";
import { useAccount } from "../account";
import { BigQr, downloadQrPng, QrCode } from "./QrCode.tsx";
import { activeBoard, useEditor, NONE } from "./store.ts";
import { useT } from "../language";

type Link = { token: string; board_id: string | null; created_at: string };

function LinkCard({ link, title, projectName, onRevoke }: { link: Link; title: string; projectName: string; onRevoke: () => void }) {
  const t = useT();
  const url = `${window.location.origin}/delad/${link.token}`;
  const [copied, setCopied] = useState(false);
  const [showQr, setShowQr] = useState(false);
  const [bigQr, setBigQr] = useState(false);
  const message = `${projectName}: ${title}`;
  const text = encodeURIComponent(`${message}\n${url}`);
  const canShare = typeof navigator !== "undefined" && typeof navigator.share === "function";

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(url);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch { /* the field can be copied by hand */ }
  };
  const share = async () => {
    try { await navigator.share({ title: message, text: message, url }); } catch { /* closed by the person */ }
  };

  return (
    <li>
      {bigQr && <BigQr text={url} title={message} onClose={() => setBigQr(false)} />}
      <strong>{title}</strong>
      <input readOnly value={url} onFocus={event => event.target.select()} aria-label={t("Länk, {name}", { name: title })} />
      <div className="tb-actions">
        <button type="button" className="wt-button small" onClick={() => void copy()}>{copied ? t("Kopierad") : t("Kopiera")}</button>
        {canShare && <button type="button" className="wt-button small" onClick={() => void share()}>{t("Dela…")}</button>}
        <button type="button" className="wt-button secondary small" aria-expanded={showQr} onClick={() => setShowQr(!showQr)}>{t("QR-kod")}</button>
        <a className="wt-button secondary small" href={url} target="_blank" rel="noreferrer">{t("Öppna")}</a>
      </div>
      <div className="tb-share-ways" aria-label={t("Skicka länken")}>
        <a href={`mailto:?subject=${encodeURIComponent(message)}&body=${text}`}>{t("E-post")}</a>
        <a href={`sms:?&body=${text}`}>{t("SMS")}</a>
        <a href={`https://wa.me/?text=${text}`} target="_blank" rel="noreferrer">WhatsApp</a>
        <button type="button" className="tb-link" onClick={onRevoke}>{t("Återkalla länken")}</button>
      </div>
      {showQr && (
        <div className="tb-qr-box">
          <QrCode text={url} label={t("QR-kod för {name}", { name: title })} />
          <div className="tb-qr-actions">
            <p className="tb-hint">{t("Skanna med mobilens kamera. Visa den på en skärm i omklädningsrummet, eller skriv ut den.")}</p>
            <button type="button" className="wt-button small" onClick={() => setBigQr(true)}>{t("Visa stort")}</button>
            <button type="button" className="wt-button secondary small" onClick={() => downloadQrPng(url, message, `QR_${message.replace(/[^\p{L}\p{N}]+/gu, "_")}.png`)}>{t("Spara som bild")}</button>
          </div>
        </div>
      )}
    </li>
  );
}

export function ShareLinks() {
  const t = useT();
  const { client } = useAccount();
  const meta = useEditor(state => state.meta);
  const board = useEditor(activeBoard);
  const boards = useEditor(state => state.document?.boards ?? NONE);
  const [links, setLinks] = useState<Link[] | null>(null);
  const [error, setError] = useState("");

  const load = useCallback(async () => {
    if (!client || !meta) return;
    const { data, error: loadError } = await client.schema("api").rpc("list_tactics_share_links", { target_project_id: meta.id });
    if (loadError) { setError(t("Länkarna kunde inte hämtas.")); setLinks([]); return; }
    setLinks(data as Link[]);
  }, [client, meta]);
  useEffect(() => { void load(); }, [load]);

  const create = async (boardId: string | null) => {
    if (!client || !meta) return;
    setError("");
    const { error: createError } = await client.schema("api").rpc("create_tactics_share_link", { target_project_id: meta.id, target_board_id: boardId });
    if (createError) { setError(t("Länken kunde inte skapas. Har projektet sparats?")); return; }
    void load();
  };
  const revoke = async (token: string) => {
    if (!client || !window.confirm(t("Återkalla länken? Den slutar fungera för alla som har den."))) return;
    const { error: revokeError } = await client.schema("api").rpc("revoke_tactics_share_link", { target_token: token });
    if (revokeError) { setError(t("Länken kunde inte återkallas.")); return; }
    void load();
  };
  const titleOf = (id: string | null) => id === null ? t("Hela projektet") : boards.find(item => item.id === id)?.name ?? t("Borttagen tavla");
  const has = (id: string | null) => links?.some(link => link.board_id === id) ?? false;

  return (
    <>
      <p className="tb-hint">{t("Alla som har länken kan se och spela upp tavlorna, utan konto och utan att logga in. Det du ändrar syns direkt i länken. Återkalla länken när den inte ska fungera längre.")}</p>
      <div className="tb-actions">
        {!has(null) && <button type="button" className="wt-button small" onClick={() => void create(null)}>{t("Skapa länk till hela projektet")}</button>}
        {board && boards.length > 1 && !has(board.id) && (
          <button type="button" className="wt-button secondary small" onClick={() => void create(board.id)}>{t("Skapa länk till {name}", { name: board.name || t("tavlan") })}</button>
        )}
      </div>
      {error && <p className="wt-error" role="alert">{error}</p>}
      {links === null ? <p className="tb-hint">{t("Laddar…")}</p> : links.length > 0 && (
        <ul className="tb-links">
          {links.map(link => (
            <LinkCard key={link.token} link={link} title={titleOf(link.board_id)} projectName={meta?.name || t("Tavla")} onRevoke={() => void revoke(link.token)} />
          ))}
        </ul>
      )}
    </>
  );
}
