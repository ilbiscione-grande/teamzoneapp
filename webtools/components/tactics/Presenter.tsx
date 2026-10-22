"use client";

// Presenting: the board alone on the whole screen, nothing to change, with
// its description and the frame's note beside it (an exercise's set-up and
// coaching points). Boards and frames are stepped through with the
// buttons or the arrow keys; Escape leaves.
import dynamic from "next/dynamic";
import { useEffect, useRef, useState } from "react";
import { ErrorBoundary } from "./ErrorBoundary.tsx";
import { activeBoard, useEditor, NONE } from "./store.ts";
import { Timeline } from "./timeline/Timeline.tsx";

const BoardStage = dynamic(() => import("./stage/BoardStage.tsx"), { ssr: false, loading: () => <div className="tb-stage" /> });

export function Presenter({ onClose }: { onClose: () => void }) {
  const root = useRef<HTMLDivElement>(null);
  const board = useEditor(activeBoard);
  const boards = useEditor(state => state.document?.boards ?? NONE);
  const frameIndex = useEditor(state => state.frameIndex);
  const description = board?.description?.trim() ?? "";
  const note = board?.frames[frameIndex]?.note?.trim() ?? "";
  const [showText, setShowText] = useState(() => !!(description || note));
  const boardIndex = boards.findIndex(item => item.id === board?.id);

  useEffect(() => {
    const state = useEditor.getState();
    state.select([]);
    state.setTool("select");
    // Whole screen where the browser allows it; a phone may keep its bars.
    root.current?.requestFullscreen?.().catch(() => {});
    return () => { if (document.fullscreenElement) void document.exitFullscreen().catch(() => {}); };
  }, []);

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      const state = useEditor.getState();
      const current = activeBoard(state);
      if (!current) return;
      if (event.key === "Escape" && !document.fullscreenElement) onClose();
      else if (event.key === "ArrowRight") { event.preventDefault(); state.setFrame(state.frameIndex + 1); }
      else if (event.key === "ArrowLeft") { event.preventDefault(); state.setFrame(state.frameIndex - 1); }
      else if (event.key === " ") { event.preventDefault(); if (state.playing) state.pause(); else state.play(); }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  if (!board) return null;
  const step = (by: number) => { const next = boards[boardIndex + by]; if (next) useEditor.getState().setBoard(next.id); };
  return (
    <div ref={root} className="tb-present" data-text={showText}>
      <header className="tb-present-top">
        {boards.length > 1 && <button type="button" className="tb-icon" onClick={() => step(-1)} disabled={boardIndex <= 0} aria-label="Föregående tavla">‹</button>}
        <strong className="tb-present-title">{board.name || "Tavla"}{boards.length > 1 && <small> {boardIndex + 1} av {boards.length}</small>}</strong>
        {boards.length > 1 && <button type="button" className="tb-icon" onClick={() => step(1)} disabled={boardIndex >= boards.length - 1} aria-label="Nästa tavla">›</button>}
        <span className="tb-spacer" />
        <button type="button" className="tb-present-toggle" aria-pressed={showText} onClick={() => setShowText(!showText)}>Beskrivning</button>
        <button type="button" className="tb-icon" onClick={onClose} aria-label="Stäng visningen" title="Stäng (Esc)">×</button>
      </header>
      <div className="tb-present-body">
        <div className="tb-center">
          <ErrorBoundary label="Tavlan"><BoardStage editable={false} /></ErrorBoundary>
          <ErrorBoundary label="Tidslinjen"><Timeline board={board} readOnly /></ErrorBoundary>
        </div>
        {showText && (
          <aside className="tb-present-text" aria-label="Beskrivning">
            {description ? <p>{description}</p> : <p className="tb-present-empty">Tavlan har ingen beskrivning. Skriv en under Tavlan i redigeringen.</p>}
            {note && (
              <>
                <h3>Ram {frameIndex + 1}</h3>
                <p>{note}</p>
              </>
            )}
          </aside>
        )}
      </div>
    </div>
  );
}
