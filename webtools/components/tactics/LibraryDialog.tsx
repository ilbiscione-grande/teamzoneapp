"use client";

// Saving in your library (decision package 13): in a training project the
// board in hand as an exercise or the whole project as a pass; in teaching
// material the project as a session. Saved again from the same board or
// project, it updates that entry. Ties to TeamZone players never go along.
import { useEffect, useState } from "react";
import { exerciseItem, lessonItem, libraryKindsFor, planItem, type LibraryKind } from "../../lib/tactics/library.ts";
import { activeBoard, useEditor, NONE } from "./store.ts";
import { useLibrary } from "./use-library.ts";

const nameLabels: Record<LibraryKind, string> = { exercise: "Övningens namn", plan: "Passets namn", lesson: "Sessionens namn" };

export function LibraryDialog({ onClose }: { onClose: () => void }) {
  const meta = useEditor(state => state.meta);
  const board = useEditor(activeBoard);
  const boards = useEditor(state => state.document?.boards ?? NONE);
  const kinds = meta ? libraryKindsFor[meta.kind] : [];
  const { items, error, save, signedIn } = useLibrary();
  const [kind, setKind] = useState<LibraryKind | undefined>(kinds[0]);
  const [title, setTitle] = useState(() => (kinds[0] === "exercise" ? board?.name : meta?.name) ?? "");
  const [theme, setTheme] = useState("");
  const [goal, setGoal] = useState("");
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState<{ created: boolean; version: number } | null>(null);
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => { if (event.key === "Escape") onClose(); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  // The entry this board or project already has, saved before.
  const existing = items?.find(item => item.kind === kind && item.source_project_id === meta?.id
    && (kind !== "exercise" || item.source_board_id === board?.id));

  const choose = (next: LibraryKind) => {
    setKind(next);
    setTitle((next === "exercise" ? board?.name : meta?.name) ?? "");
  };

  const submit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!meta || !board || !kind || !title.trim()) return;
    const item = kind === "exercise" ? exerciseItem(board, title.trim())
      : kind === "plan" ? planItem(boards, title.trim(), theme.trim(), goal.trim())
      : lessonItem(boards, title.trim());
    setBusy(true);
    const saved = await save(item, meta.id, kind === "exercise" ? board.id : null);
    setBusy(false);
    if (saved) setDone({ created: saved.created, version: saved.version });
  };

  return (
    <div className="tb-modal" role="dialog" aria-modal="true" aria-label="Spara i biblioteket" onClick={event => { if (event.target === event.currentTarget) onClose(); }}>
      <form className="tb-modal-card" onSubmit={submit}>
        <div className="tb-modal-head">
          <h2>Spara i biblioteket</h2>
          <button type="button" className="tb-modal-close" aria-label="Stäng" onClick={onClose}>×</button>
        </div>
        {!signedIn ? (
          <>
            <p>Logga in med ditt TeamZone-konto för att spara övningar, pass och sessioner i ditt bibliotek.</p>
            <div className="tb-actions"><button type="button" className="wt-button small" onClick={onClose}>Stäng</button></div>
          </>
        ) : kinds.length === 0 ? (
          <>
            <p>Matchens tavlor hör till laget och sparas inte i biblioteket. Spara dem som mall om du vill återanvända dem.</p>
            <div className="tb-actions"><button type="button" className="wt-button small" onClick={onClose}>Stäng</button></div>
          </>
        ) : done ? (
          <>
            <p>{done.created
              ? `${title.trim()} är sparad i ditt bibliotek.`
              : `${title.trim()} är uppdaterad i ditt bibliotek (version ${done.version}).`} Du hittar den under Ditt bibliotek på startsidan.</p>
            <div className="tb-actions"><button type="button" className="wt-button small" onClick={onClose}>Stäng</button></div>
          </>
        ) : (
          <>
            <p className="tb-hint">Biblioteket är dina övningar, pass och sessioner att använda igen. Kopplingar till spelare i laget och spelarnas namn följer inte med.</p>
            {kinds.length > 1 && (
              <div className="tb-field" role="radiogroup" aria-label="Vad som sparas">
                {kinds.map(value => (
                  <label key={value} className="tb-check">
                    <input type="radio" name="library-kind" checked={kind === value} onChange={() => choose(value)} />
                    {value === "exercise" ? `Tavlan ${board?.name || "Tavla"} som övning` : `Projektet som pass (${boards.length} ${boards.length === 1 ? "övning" : "övningar"})`}
                  </label>
                ))}
              </div>
            )}
            <label className="tb-field">{kind ? nameLabels[kind] : "Namn"}
              <input value={title} maxLength={120} required onChange={event => setTitle(event.target.value)} />
            </label>
            {kind === "plan" && (
              <>
                <label className="tb-field">Tema<input value={theme} maxLength={200} placeholder="T.ex. press och återerövring" onChange={event => setTheme(event.target.value)} /></label>
                <label className="tb-field">Passets mål<textarea rows={3} maxLength={2000} value={goal} onChange={event => setGoal(event.target.value)} /></label>
                <p className="tb-hint">Varje tavla blir en övning i passet, med uppgifterna du fyllt i under Övningen.</p>
              </>
            )}
            {kind === "exercise" && <p className="tb-hint">Uppgifterna under Övningen och tavlans beskrivning följer med.</p>}
            {existing && <p className="tb-hint">{kind === "exercise" ? "Tavlan" : "Projektet"} finns redan i biblioteket som {existing.title} och uppdateras till en ny version.</p>}
            {error && <p className="wt-error" role="alert">{error}</p>}
            <div className="tb-actions">
              <button type="submit" className="wt-button small" disabled={busy || !title.trim()}>{busy ? "Sparar…" : existing ? "Uppdatera i biblioteket" : "Spara i biblioteket"}</button>
              <button type="button" className="wt-button secondary small" onClick={onClose}>Avbryt</button>
            </div>
          </>
        )}
      </form>
    </div>
  );
}
