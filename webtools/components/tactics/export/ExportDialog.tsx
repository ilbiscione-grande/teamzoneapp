"use client";

// Making a PDF: which boards, and for animated ones which frames and
// whether the moves show as arrows. Each picture is drawn off screen in
// turn, then the pages are put together.
import dynamic from "next/dynamic";
import { useEffect, useRef, useState } from "react";
import { layoutPages, pdfFileName, type FrameChoice } from "../../../lib/tactics/pdf-layout.ts";
import { movesInto, type Trail } from "../../../lib/tactics/marks.ts";
import type { Board, TacticsObject } from "../../../lib/tactics/model.ts";
import { activeBoard, useEditor, NONE } from "../store.ts";
import { kindLabels } from "../TopBar.tsx";
import { download } from "../timeline/video-export.ts";
import { buildPdf } from "./pdf.ts";

const OffscreenBoard = dynamic(() => import("./OffscreenBoard.tsx"), { ssr: false });

type Job = { board: Board; objects: TacticsObject[]; moves: Trail[]; done: (picture: string) => void };

/** A frame's moves for its picture: into it, or with only the last frame shown, the whole play up to it. */
function movesFor(board: Board, frameIndex: number, choice: FrameChoice): Trail[] {
  if (choice !== "last") return movesInto(board.frames, frameIndex);
  return board.frames.flatMap((_, index) => index <= frameIndex ? movesInto(board.frames, index) : []);
}

export function ExportDialog({ onClose }: { onClose: () => void }) {
  const meta = useEditor(state => state.meta);
  const boards = useEditor(state => state.document?.boards ?? NONE);
  const board = useEditor(activeBoard);
  const [which, setWhich] = useState<"this" | "all">("this");
  const [frames, setFrames] = useState<FrameChoice>("grid");
  const [showMoves, setShowMoves] = useState(true);
  const [job, setJob] = useState<Job | null>(null);
  const [progress, setProgress] = useState<string | null>(null);
  const [error, setError] = useState("");
  const working = useRef(false);
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => { if (event.key === "Escape" && !working.current) onClose(); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);
  if (!meta || !board) return null;
  const animated = (which === "all" ? boards : [board]).some(item => item.frames.length > 1);

  const picture = (target: Board, objects: TacticsObject[], moves: Trail[]) =>
    new Promise<string>(resolve => setJob({ board: target, objects, moves, done: resolve }));

  const make = async () => {
    working.current = true;
    setError("");
    try {
      const indexes = which === "all" ? boards.map((_, index) => index) : [boards.indexOf(board)];
      const pages = layoutPages(boards, indexes, frames);
      const wanted = [...new Set(pages.flatMap(page => page.placements.map(item => `${item.boardIndex}:${item.frameIndex}`)))];
      const pictures = new Map<string, string>();
      for (const [done, key] of wanted.entries()) {
        setProgress(`Ritar ${done + 1} av ${wanted.length}…`);
        const [boardIndex, frameIndex] = key.split(":").map(Number);
        const target = boards[boardIndex];
        pictures.set(key, await picture(target, target.frames[frameIndex].objects, showMoves ? movesFor(target, frameIndex, frames) : []));
      }
      setJob(null);
      setProgress("Skapar PDF…");
      const blob = await buildPdf({ projectName: meta.name || "Tacticsboard", subtitle: [kindLabels[meta.kind], meta.teamName].filter(Boolean).join(" · "), pages, pictures });
      download(blob, pdfFileName(meta.name));
      onClose();
    } catch {
      setError("PDF:en kunde inte skapas. Försök igen.");
    } finally {
      working.current = false;
      setProgress(null);
      setJob(null);
    }
  };

  return (
    <div className="tb-modal" role="dialog" aria-modal="true" aria-label="PDF" onClick={event => { if (event.target === event.currentTarget && !working.current) onClose(); }}>
      <div className="tb-modal-card">
        <div className="tb-modal-head">
          <h2>PDF</h2>
          <button type="button" className="tb-modal-close" aria-label="Stäng" disabled={progress !== null} onClick={onClose}>×</button>
        </div>
        {boards.length > 1 && (
          <fieldset className="tb-choice">
            <legend>Tavlor</legend>
            <label><input type="radio" checked={which === "this"} onChange={() => setWhich("this")} />{board.name || "Den här tavlan"}</label>
            <label><input type="radio" checked={which === "all"} onChange={() => setWhich("all")} />Alla {boards.length} tavlor</label>
          </fieldset>
        )}
        {animated && (
          <fieldset className="tb-choice">
            <legend>Frames</legend>
            <label><input type="radio" checked={frames === "grid"} onChange={() => setFrames("grid")} />Alla frames, fyra per sida</label>
            <label><input type="radio" checked={frames === "each"} onChange={() => setFrames("each")} />Alla frames, en per sida</label>
            <label><input type="radio" checked={frames === "last"} onChange={() => setFrames("last")} />Bara sista framen</label>
          </fieldset>
        )}
        {animated && (
          <label className="tb-check">
            <input type="checkbox" checked={showMoves} onChange={event => setShowMoves(event.target.checked)} />
            Visa rörelser med pilar{frames === "last" ? " (hela förloppet på en bild)" : ""}
          </label>
        )}
        <p className="tb-hint">A4 liggande, med projektets och tavlans namn, numret och anteckningen för varje frame, och tavlans beskrivning.</p>
        {error && <p className="wt-error" role="alert">{error}</p>}
        <div className="tb-actions">
          <button type="button" className="wt-button" disabled={progress !== null} onClick={() => void make()}>{progress ?? "Skapa PDF"}</button>
        </div>
        {job && <OffscreenBoard board={job.board} objects={job.objects} moves={job.moves} onPicture={job.done} />}
      </div>
    </div>
  );
}
