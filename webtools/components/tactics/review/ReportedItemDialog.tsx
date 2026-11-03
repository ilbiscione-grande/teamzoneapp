"use client";

// A reported item whole, for support (plan item 16): every board small with
// all it says in words, the reports, and the decision with a note for the
// audit: hide it from the library, or keep it shown.
import { useEffect, useState } from "react";
import { libraryKindLabels } from "../../../lib/tactics/library.ts";
import { boardTexts, noteReady, reviewStatus, type ReportedItem, type ReportedItemWhole } from "../../../lib/tactics/reports.ts";
import { ProjectThumb } from "../home/ProjectThumb.tsx";
import { ReportList } from "./ReportList.tsx";
import "../share.css";

type Props = {
  item: ReportedItem;
  load: (id: string) => Promise<ReportedItemWhole | null>;
  decide: (id: string, hide: boolean, note: string) => Promise<boolean>;
  error: string;
  onClose: (changed: boolean) => void;
};

export function ReportedItemDialog({ item, load, decide, error, onClose }: Props) {
  const [whole, setWhole] = useState<ReportedItemWhole | null | undefined>(undefined);
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  useEffect(() => { void load(item.id).then(setWhole); }, [item.id]);
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => { if (event.key === "Escape") onClose(false); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  const choose = async (hide: boolean) => {
    if (!noteReady(note)) return;
    setBusy(true);
    const done = await decide(item.id, hide, note);
    setBusy(false);
    if (done) onClose(true);
  };
  const shown = whole ?? item;

  return (
    <div className="tb-modal" role="dialog" aria-modal="true" aria-label={`Granska ${item.title}`} onClick={event => { if (event.target === event.currentTarget) onClose(false); }}>
      <div className="tb-modal-card tb-review-card">
        <div className="tb-modal-head">
          <h2>Granska</h2>
          <button type="button" className="tb-modal-close" aria-label="Stäng" onClick={() => onClose(false)}>×</button>
        </div>
        <div>
          <strong>{item.title}</strong>
          <p className="tb-hint">{[libraryKindLabels[item.kind], `av ${item.author}`, item.club_name && `bara ${item.club_name}`, `version ${item.version}`].filter(Boolean).join(" · ")}</p>
          <p className="tb-hint"><strong>{reviewStatus(shown)}</strong></p>
        </div>
        <ReportList reports={shown.reports} />
        {whole === undefined ? <p className="wt-status">Laddar…</p> : whole === null ? null : (
          <ol className="tb-review-boards">
            {(whole.document.boards ?? []).map((board, index) => (
              <li key={board.id ?? index}>
                <ProjectThumb preview={{ view: board.view, teams: board.teams, objects: board.frames?.[0]?.objects ?? [] }} />
                <ul>{boardTexts(board).map(text => <li key={text}>{text}</li>)}</ul>
              </li>
            ))}
          </ol>
        )}
        <label className="tb-field">Motivering (sparas i loggen)
          <textarea value={note} rows={2} maxLength={1000} onChange={event => setNote(event.target.value)}
            placeholder="T.ex. Riktiga spelares namn, eller Inget olämpligt" />
        </label>
        {error && <p className="wt-error" role="alert">{error}</p>}
        <div className="tb-actions">
          <button type="button" className="wt-button secondary small" disabled={busy || !noteReady(note)} onClick={() => void choose(false)}>
            {shown.hidden ? "Visa igen" : "Behåll"}
          </button>
          <button type="button" className="wt-button small" disabled={busy || !noteReady(note)} onClick={() => void choose(true)}>Dölj ur biblioteket</button>
        </div>
        <p className="tb-hint">Dold syns den bara för den som delat den, och den kan inte delas igen. De som redan använt den behåller sina kopior.</p>
      </div>
    </div>
  );
}
