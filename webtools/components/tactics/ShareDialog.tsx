"use client";

// Every way the boards leave the editor, in one dialog under the top bar's
// share button: the part of the pitch to show, a link to watch them, a PDF,
// a video of the board in hand,
// the project as a file, publishing in a club's library and, in a training
// project, the board put in one of the team's coming sessions.
import { useEffect, useState, type ReactNode } from "react";
import { exportFileName, exportProject } from "../../lib/tactics/transfer.ts";
import { activeBoard, useEditor } from "./store.ts";
import { ShareLinks } from "./ShareLinks.tsx";
import { ExportDialog } from "./export/ExportDialog.tsx";
import { PublishDialog } from "./PublishDialog.tsx";
import { TrainingLinkDialog } from "./TrainingLinkDialog.tsx";
import { canRecord, download, recordBoard, useRecording } from "./timeline/video-export.ts";
import { setCrop } from "./stage/CropFrame.tsx";

type Inner = "pdf" | "publish" | "training" | null;

function Way({ title, hint, children }: { title: string; hint: string; children: ReactNode }) {
  return (
    <li>
      <div><strong>{title}</strong><p className="tb-hint">{hint}</p></div>
      {children}
    </li>
  );
}

/** onCrop: closes the dialog for the crop to be chosen on the board. */
export function ShareDialog({ onClose, onCrop }: { onClose: () => void; onCrop: () => void }) {
  const meta = useEditor(state => state.meta);
  const board = useEditor(activeBoard);
  const tilt = useEditor(state => state.tilt);
  const recording = useRecording(state => state.share);
  const [inner, setInner] = useState<Inner>(null);
  const [error, setError] = useState("");
  const owner = meta?.access === "owner";
  useEffect(() => {
    if (inner) return;
    const onKey = (event: KeyboardEvent) => { if (event.key === "Escape" && recording === null) onClose(); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [inner, onClose, recording]);
  if (!meta || !board) return null;

  const animated = board.frames.length > 1;
  const record = async () => {
    setError("");
    try {
      const video = await recordBoard();
      if (!video) setError("Webbläsaren kan inte spela in video här.");
      else download(video.blob, `${(board.name || "tavla").replace(/[^\p{L}\p{N}]+/gu, "_")}.${video.extension}`);
    } catch {
      setError("Videon kunde inte spelas in.");
    }
  };
  const exportFile = () => {
    const document = useEditor.getState().document;
    if (!document) return;
    download(new Blob([exportProject(meta.name, meta.kind, document)], { type: "application/json" }), exportFileName(meta.name));
  };

  if (inner === "pdf") return <ExportDialog onClose={() => setInner(null)} />;
  if (inner === "publish") return <PublishDialog onClose={() => setInner(null)} />;
  if (inner === "training") return <TrainingLinkDialog board={board} onClose={() => setInner(null)} />;
  return (
    <div className="tb-modal" role="dialog" aria-modal="true" aria-label="Dela"
      onClick={event => { if (event.target === event.currentTarget && recording === null) onClose(); }}>
      <div className="tb-modal-card tb-share-card">
        <div className="tb-modal-head">
          <h2>Dela</h2>
          <button type="button" className="tb-modal-close" aria-label="Stäng" disabled={recording !== null} onClick={onClose}>×</button>
        </div>
        <section className="tb-share-section">
          <h3>Utsnitt</h3>
          <ul className="tb-share-list">
            <Way title={board.crop ? "En del av planen" : "Hela planen"}
              hint={board.crop
                ? `Bara den del av ${board.name || "tavlan"} du valt visas i PDF, video, visningsläget och delade länkar.${tilt ? " Videon i 3D visar hela planen." : ""}`
                : "Välj en del av planen för att bara visa det som händer där, i PDF, video, visningsläget och delade länkar."}>
              <span className="tb-actions">
                {board.crop && <button type="button" className="wt-button secondary small" disabled={recording !== null} onClick={() => setCrop(board.id, null)}>Hela planen</button>}
                <button type="button" className="wt-button secondary small" disabled={recording !== null} onClick={onCrop}>{board.crop ? "Ändra…" : "Välj utsnitt…"}</button>
              </span>
            </Way>
          </ul>
        </section>
        <section className="tb-share-section">
          <h3>Länk att titta på</h3>
          {owner ? <ShareLinks /> : <p className="tb-hint">{meta.ownerName?.trim() || "En annan ledare"} äger projektet och delar länkar till det.</p>}
        </section>
        <section className="tb-share-section">
          <h3>Spara och skicka</h3>
          <ul className="tb-share-list">
            <Way title="PDF" hint="Tavlorna på A4 med beskrivning och anteckningar, att skriva ut eller skicka.">
              <button type="button" className="wt-button secondary small" disabled={recording !== null} onClick={() => setInner("pdf")}>Skapa PDF…</button>
            </Way>
            {canRecord() && (
              <Way title="Video" hint={animated ? `${board.name || "Tavlan"} spelas upp från början och sparas som video.` : "Lägg till en frame till för att kunna spela in tavlan."}>
                <button type="button" className="wt-button secondary small" disabled={!animated || recording !== null} onClick={() => void record()}>
                  {recording !== null ? `Spelar in ${Math.round(recording * 100)} %` : "Spela in"}
                </button>
              </Way>
            )}
            <Way title="Fil" hint="Hela projektet som en fil, att importera på startsidan, även på ett annat konto.">
              <button type="button" className="wt-button secondary small" disabled={recording !== null} onClick={exportFile}>Spara som fil</button>
            </Way>
          </ul>
          {error && <p className="wt-error" role="alert">{error}</p>}
        </section>
        {(owner || meta.kind === "training") && (
          <section className="tb-share-section">
            <h3>I TeamZone</h3>
            <ul className="tb-share-list">
              {owner && (
                <Way title="Klubbens bibliotek" hint="Publicera projektet eller tavlan så att klubbens ledare hittar den.">
                  <button type="button" className="wt-button secondary small" disabled={recording !== null} onClick={() => setInner("publish")}>Publicera…</button>
                </Way>
              )}
              {meta.kind === "training" && (
                <Way title="Träningspass" hint={`${board.name || "Tavlan"} som övning i ett av lagets kommande pass.`}>
                  <button type="button" className="wt-button secondary small" disabled={recording !== null} onClick={() => setInner("training")}>Lägg i ett pass…</button>
                </Way>
              )}
            </ul>
          </section>
        )}
      </div>
    </div>
  );
}
