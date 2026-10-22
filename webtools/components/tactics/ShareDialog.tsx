"use client";

// Sharing: a link to the whole project or the board in hand, to copy and
// send. Anyone with it watches and plays the boards without an account,
// always as last saved, until the link is revoked.
import { useCallback, useEffect, useState } from "react";
import { useAccount } from "../account";
import { activeBoard, useEditor, NONE } from "./store.ts";

type Link = { token: string; board_id: string | null; created_at: string };

export function ShareDialog({ onClose }: { onClose: () => void }) {
  const { client } = useAccount();
  const meta = useEditor(state => state.meta);
  const board = useEditor(activeBoard);
  const boards = useEditor(state => state.document?.boards ?? NONE);
  const [links, setLinks] = useState<Link[] | null>(null);
  const [error, setError] = useState("");
  const [copied, setCopied] = useState("");
  const url = (token: string) => `${window.location.origin}/delad/${token}`;

  const load = useCallback(async () => {
    if (!client || !meta) return;
    const { data, error: loadError } = await client.schema("api").rpc("list_tactics_share_links", { target_project_id: meta.id });
    if (loadError) { setError("Länkarna kunde inte hämtas."); setLinks([]); return; }
    setLinks(data as Link[]);
  }, [client, meta]);
  useEffect(() => { void load(); }, [load]);
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => { if (event.key === "Escape") onClose(); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  const copy = async (token: string) => {
    try {
      await navigator.clipboard.writeText(url(token));
      setCopied(token);
    } catch {
      setError("Kopiera länken från fältet.");
    }
  };
  const create = async (boardId: string | null) => {
    if (!client || !meta) return;
    setError("");
    const { data, error: createError } = await client.schema("api").rpc("create_tactics_share_link", { target_project_id: meta.id, target_board_id: boardId });
    if (createError) { setError("Länken kunde inte skapas. Har projektet sparats?"); return; }
    await load();
    void copy(String(data));
  };
  const revoke = async (token: string) => {
    if (!client || !window.confirm("Återkalla länken? Den slutar fungera för alla som har den.")) return;
    const { error: revokeError } = await client.schema("api").rpc("revoke_tactics_share_link", { target_token: token });
    if (revokeError) { setError("Länken kunde inte återkallas."); return; }
    void load();
  };
  const boardName = (id: string | null) => id === null ? "Hela projektet" : `Tavla: ${boards.find(item => item.id === id)?.name ?? "borttagen"}`;
  const has = (id: string | null) => links?.some(link => link.board_id === id) ?? false;

  return (
    <div className="tb-modal" role="dialog" aria-modal="true" aria-label="Dela" onClick={event => { if (event.target === event.currentTarget) onClose(); }}>
      <div className="tb-modal-card">
        <div className="tb-modal-head">
          <h2>Dela</h2>
          <button type="button" className="tb-modal-close" aria-label="Stäng" onClick={onClose}>×</button>
        </div>
        <p className="tb-hint">Den som har länken kan se och spela upp tavlorna utan att logga in. Det du ändrar syns direkt i länken.</p>
        <div className="tb-actions">
          <button type="button" className="wt-button small" disabled={has(null)} onClick={() => void create(null)}>Länk till hela projektet</button>
          {board && boards.length > 1 && (
            <button type="button" className="wt-button secondary small" disabled={has(board.id)} onClick={() => void create(board.id)}>Länk till {board.name || "tavlan"}</button>
          )}
        </div>
        {error && <p className="wt-error" role="alert">{error}</p>}
        {links === null ? <p className="tb-hint">Laddar…</p> : links.length === 0 ? null : (
          <ul className="tb-links">
            {links.map(link => (
              <li key={link.token}>
                <strong>{boardName(link.board_id)}</strong>
                <input readOnly value={url(link.token)} onFocus={event => event.target.select()} aria-label={`Länk, ${boardName(link.board_id)}`} />
                <div className="tb-actions">
                  <button type="button" className="wt-button small" onClick={() => void copy(link.token)}>{copied === link.token ? "Kopierad" : "Kopiera"}</button>
                  <a className="wt-button secondary small" href={url(link.token)} target="_blank" rel="noreferrer">Öppna</a>
                  <button type="button" className="wt-button secondary small" onClick={() => void revoke(link.token)}>Återkalla</button>
                </div>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}
