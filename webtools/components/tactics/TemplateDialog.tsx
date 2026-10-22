"use client";

// Saving as a template: the whole project or only the board in hand, under
// a name. Ties to TeamZone players never go along; the players' names only
// when asked. A name you already have replaces that template.
import { useEffect, useState } from "react";
import { boardsForTemplate } from "../../lib/tactics/templates.ts";
import { activeBoard, useEditor, NONE } from "./store.ts";
import { useTemplates } from "./use-templates.ts";

export function TemplateDialog({ onClose }: { onClose: () => void }) {
  const meta = useEditor(state => state.meta);
  const board = useEditor(activeBoard);
  const boards = useEditor(state => state.document?.boards ?? NONE);
  const { templates, error, save } = useTemplates();
  const [scope, setScope] = useState<"project" | "board">(boards.length > 1 ? "project" : "board");
  const [name, setName] = useState(() => (boards.length > 1 ? meta?.name : board?.name) ?? "");
  const [keepNames, setKeepNames] = useState(false);
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState(false);
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => { if (event.key === "Escape") onClose(); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  const submit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!meta || !board || !name.trim()) return;
    const existing = templates?.find(item => item.name.trim().toLowerCase() === name.trim().toLowerCase());
    if (existing && !window.confirm(`Du har redan en mall som heter ${existing.name}. Ersätta den?`)) return;
    setBusy(true);
    const ok = await save(name.trim(), meta.kind, boardsForTemplate(scope === "project" ? boards : [board], keepNames));
    setBusy(false);
    if (ok) setDone(true);
  };

  return (
    <div className="tb-modal" role="dialog" aria-modal="true" aria-label="Spara som mall" onClick={event => { if (event.target === event.currentTarget) onClose(); }}>
      <form className="tb-modal-card" onSubmit={submit}>
        <div className="tb-modal-head">
          <h2>Spara som mall</h2>
          <button type="button" className="tb-modal-close" aria-label="Stäng" onClick={onClose}>×</button>
        </div>
        {done ? (
          <>
            <p>Mallen {name.trim()} är sparad. Använd den när du skapar ett nytt projekt, eller under + Tavla i ett projekt.</p>
            <div className="tb-actions"><button type="button" className="wt-button small" onClick={onClose}>Stäng</button></div>
          </>
        ) : (
          <>
            <p className="tb-hint">En mall är tavlor att börja från: spelare, linjer, ramar och anteckningar följer med. Kopplingar till spelare i laget följer inte med.</p>
            {boards.length > 1 && (
              <div className="tb-field" role="radiogroup" aria-label="Vad som sparas">
                <label className="tb-check"><input type="radio" name="scope" checked={scope === "project"} onChange={() => { setScope("project"); setName(meta?.name ?? ""); }} />Hela projektet ({boards.length} tavlor)</label>
                <label className="tb-check"><input type="radio" name="scope" checked={scope === "board"} onChange={() => { setScope("board"); setName(board?.name ?? ""); }} />Bara tavlan {board?.name || "Tavla"}</label>
              </div>
            )}
            <label className="tb-field">Mallens namn<input value={name} maxLength={80} required onChange={event => setName(event.target.value)} /></label>
            <label className="tb-check"><input type="checkbox" checked={keepNames} onChange={event => setKeepNames(event.target.checked)} />Behåll spelarnas namn</label>
            {error && <p className="wt-error" role="alert">{error}</p>}
            <div className="tb-actions">
              <button type="submit" className="wt-button small" disabled={busy || !name.trim()}>{busy ? "Sparar…" : "Spara mallen"}</button>
              <button type="button" className="wt-button secondary small" onClick={onClose}>Avbryt</button>
            </div>
          </>
        )}
      </form>
    </div>
  );
}
