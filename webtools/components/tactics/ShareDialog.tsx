"use client";

// Every way the boards leave the editor, in one dialog under the top bar's
// share button: the part of the pitch to show, a link to watch them, a PDF,
// a video of the board in hand,
// the project as a file, publishing in the library and, in a training
// project with a team, the board put in one of the team's coming sessions.
import { useEffect, useState, type ReactNode } from "react";
import { exportFileName, exportProject } from "../../lib/tactics/transfer.ts";
import { useAccount } from "../account";
import { activeBoard, useEditor } from "./store.ts";
import { ShareLinks } from "./ShareLinks.tsx";
import { ExportDialog } from "./export/ExportDialog.tsx";
import { PublishDialog } from "./PublishDialog.tsx";
import { TrainingLinkDialog } from "./TrainingLinkDialog.tsx";
import { canRecord, download, recordBoard, useRecording } from "./timeline/video-export.ts";
import { setCrop } from "./stage/CropFrame.tsx";
import { useT } from "../language";

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
  const t = useT();
  const meta = useEditor(state => state.meta);
  const board = useEditor(activeBoard);
  const tilt = useEditor(state => state.tilt);
  const recording = useRecording(state => state.share);
  const [inner, setInner] = useState<Inner>(null);
  const [error, setError] = useState("");
  const owner = meta?.access === "owner";
  // A training session needs a team in TeamZone; without one the way is not shown.
  const { connections } = useAccount();
  const toTraining = meta?.kind === "training" && (!!meta.teamId || (connections?.length ?? 0) > 0);
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
      if (!video) setError(t("Webbläsaren kan inte spela in video här."));
      else {
        download(video.blob, `${(board.name || t("tavla")).replace(/[^\p{L}\p{N}]+/gu, "_")}.${video.extension}`);
        onClose();
      }
    } catch {
      setError(t("Videon kunde inte spelas in."));
    }
  };
  const exportFile = () => {
    const document = useEditor.getState().document;
    if (!document) return;
    download(new Blob([exportProject(meta.name, meta.kind, document)], { type: "application/json" }), exportFileName(meta.name));
  };

  // Out of the way while it records, so the pitch shows; it comes back only if the recording failed.
  if (recording !== null) return null;
  if (inner === "pdf") return <ExportDialog onClose={() => setInner(null)} />;
  if (inner === "publish") return <PublishDialog onClose={() => setInner(null)} />;
  if (inner === "training") return <TrainingLinkDialog board={board} onClose={() => setInner(null)} />;
  return (
    <div className="tb-modal" role="dialog" aria-modal="true" aria-label={t("Dela")}
      onClick={event => { if (event.target === event.currentTarget && recording === null) onClose(); }}>
      <div className="tb-modal-card tb-share-card">
        <div className="tb-modal-head">
          <h2>{t("Dela")}</h2>
          <button type="button" className="tb-modal-close" aria-label={t("Stäng")} disabled={recording !== null} onClick={onClose}>×</button>
        </div>
        <section className="tb-share-section">
          <h3>{t("Utsnitt")}</h3>
          <ul className="tb-share-list">
            <Way title={board.crop ? t("En del av planen") : t("Hela planen")}
              hint={board.crop
                ? `${t("Bara den del av {name} du valt visas i PDF, video, visningsläget och delade länkar.", { name: board.name || t("tavlan") })}${tilt ? t(" I 3D blir videon den del av den lutade planen där utsnittet syns.") : ""}`
                : t("Välj en del av planen för att bara visa det som händer där, i PDF, video, visningsläget och delade länkar.")}>
              <span className="tb-actions">
                {board.crop && <button type="button" className="wt-button secondary small" disabled={recording !== null} onClick={() => setCrop(board.id, null)}>{t("Hela planen")}</button>}
                <button type="button" className="wt-button secondary small" disabled={recording !== null} onClick={onCrop}>{board.crop ? t("Ändra…") : t("Välj utsnitt…")}</button>
              </span>
            </Way>
          </ul>
        </section>
        <section className="tb-share-section">
          <h3>{t("Länk att titta på")}</h3>
          {owner ? <ShareLinks /> : <p className="tb-hint">{t("{name} äger projektet och delar länkar till det.", { name: meta.ownerName?.trim() || t("En annan ledare") })}</p>}
        </section>
        <section className="tb-share-section">
          <h3>{t("Spara och skicka")}</h3>
          <ul className="tb-share-list">
            <Way title={t("PDF")} hint={t("Tavlorna på A4 med beskrivning och anteckningar, att skriva ut eller skicka.")}>
              <button type="button" className="wt-button secondary small" disabled={recording !== null} onClick={() => setInner("pdf")}>{t("Skapa PDF…")}</button>
            </Way>
            {canRecord() && (
              <Way title={t("Video")} hint={animated ? t("{name} spelas upp från början och sparas som video.", { name: board.name || t("Tavlan") }) : t("Lägg till en frame till för att kunna spela in tavlan.")}>
                <button type="button" className="wt-button secondary small" disabled={!animated || recording !== null} onClick={() => void record()}>
                  {recording !== null ? t("Spelar in {percent} %", { percent: Math.round(recording * 100) }) : t("Spela in")}
                </button>
              </Way>
            )}
            <Way title={t("Fil")} hint={t("Hela projektet som en fil, att importera på startsidan, även på ett annat konto.")}>
              <button type="button" className="wt-button secondary small" disabled={recording !== null} onClick={exportFile}>{t("Spara som fil")}</button>
            </Way>
          </ul>
          {error && <p className="wt-error" role="alert">{error}</p>}
        </section>
        {(owner || toTraining) && (
          <section className="tb-share-section">
            <h3>{t("Publicera")}</h3>
            <ul className="tb-share-list">
              {owner && (
                <Way title={t("Biblioteket")} hint={t("Publicera projektet eller tavlan så att andra tränare hittar den.")}>
                  <button type="button" className="wt-button secondary small" disabled={recording !== null} onClick={() => setInner("publish")}>{t("Publicera…")}</button>
                </Way>
              )}
              {toTraining && (
                <Way title={t("Träningspass")} hint={t("{name} som övning i ett av lagets kommande pass.", { name: board.name || t("Tavlan") })}>
                  <button type="button" className="wt-button secondary small" disabled={recording !== null} onClick={() => setInner("training")}>{t("Lägg i ett pass…")}</button>
                </Way>
              )}
            </ul>
          </section>
        )}
      </div>
    </div>
  );
}
