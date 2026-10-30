"use client";

// A shared link's page: the boards to watch and play, nothing to change.
// The board and its timeline are the editor's own, read-only. Made for a
// phone: a large play button to start, a swipe for the next frame and a tap
// to play or pause, and the frame's note under the board. The TZ mark sits
// on the board's corner, the header keeps its room for the name.
import dynamic from "next/dynamic";
import Link from "next/link";
import { useEffect, useState } from "react";
import { normalizeDocument } from "../../lib/tactics/document.ts";
import type { SharedTactics } from "../../lib/tactics/shared.ts";
import { ErrorBoundary } from "./ErrorBoundary.tsx";
import { BigQr } from "./QrCode.tsx";
import { Presenter } from "./Presenter.tsx";
import { MyNumber } from "./MyNumber.tsx";
import { SharedCaption } from "./SharedCaption.tsx";
import { activeBoard, stepFrame, togglePlay, useEditor, NONE } from "./store.ts";
import { Timeline } from "./timeline/Timeline.tsx";
import { kindLabels } from "./TopBar.tsx";
import "./tactics.css";

const BoardStage = dynamic(() => import("./stage/BoardStage.tsx"), { ssr: false, loading: () => <div className="tb-stage" /> });

/** back: a way back up, for a project seen through a shared folder. */
export function SharedViewer({ shared, back }: { shared: SharedTactics; back?: { href: string; label: string } }) {
  const [ready, setReady] = useState(false);
  const [qr, setQr] = useState(false);
  const [presenting, setPresenting] = useState(false);
  const board = useEditor(activeBoard);
  const boards = useEditor(state => state.document?.boards ?? NONE);
  const boardId = useEditor(state => state.boardId);
  const playing = useEditor(state => state.playing);
  const moved = useEditor(state => state.playhead > 0);
  // Until the board is first played or moved on, a large play button over it; again on another board.
  const [startedOn, setStartedOn] = useState<string | null>(null);
  useEffect(() => { if (playing || moved) setStartedOn(boardId); }, [playing, moved, boardId]);
  useEffect(() => {
    const document = normalizeDocument({ boards: shared.boards, branding: shared.branding });
    useEditor.getState().load({
      id: "shared", name: shared.name, kind: shared.kind, teamzone_team_id: null, team_name: shared.team_name,
      board_count: document.boards.length, revision: 0, created_at: shared.updated_at, updated_at: shared.updated_at, document,
    }, document);
    setReady(true);
  }, [shared]);
  if (!ready || !board) return null;
  if (presenting) return <div className="tb-viewer"><Presenter viewer onClose={() => setPresenting(false)} /></div>;
  return (
    <div className="tb-editor tb-viewer">
      <header className="tb-top">
        <div className="tb-top-row">
          {back && <Link href={back.href} className="tb-back" aria-label={back.label} title={back.label}>‹</Link>}
          <div className="tb-viewer-title">
            <strong>{shared.name}</strong>
            <span>{[kindLabels[shared.kind], shared.team_name].filter(Boolean).join(" · ")}</span>
          </div>
          <span className="tb-spacer" />
          <MyNumber boards={boards} />
          <button type="button" className="tb-icon tb-pdf" onClick={() => setPresenting(true)} aria-label="Visa i helskärm" title="Visa i helskärm med beskrivning">⛶</button>
          <button type="button" className="tb-icon tb-pdf" onClick={() => setQr(true)} title="Visa länken som QR-kod">QR</button>
        </div>
        {/* A phone chooses the board from a list, not a row of tabs to scroll. */}
        {boards.length > 1 && (
          <select className="tb-viewer-boards" aria-label="Tavla" value={boardId ?? ""} onChange={event => useEditor.getState().setBoard(event.target.value)}>
            {boards.map((item, index) => <option key={item.id} value={item.id}>{item.name || `Tavla ${index + 1}`}</option>)}
          </select>
        )}
        {boards.length > 1 && (
          <div className="tb-boards" role="tablist" aria-label="Tavlor">
            {boards.map(item => (
              <span key={item.id} className="tb-board-tab" data-active={item.id === boardId}>
                <button type="button" role="tab" aria-selected={item.id === boardId} onClick={() => useEditor.getState().setBoard(item.id)}>{item.name || "Tavla"}</button>
              </span>
            ))}
          </div>
        )}
      </header>
      {qr && <BigQr text={window.location.href} title={shared.name} onClose={() => setQr(false)} />}
      <div className="tb-center">
        <div className="tb-viewer-board">
          <ErrorBoundary label="Tavlan">
            <BoardStage editable={false} onSwipe={stepFrame} onTap={togglePlay} tiltButton />
          </ErrorBoundary>
          <span className="tb-viewer-mark" aria-hidden="true">TZ</span>
          {board.frames.length > 1 && startedOn !== boardId && (
            <button type="button" className="tb-viewer-start" aria-label="Spela upp" onClick={() => useEditor.getState().play()}>▶</button>
          )}
        </div>
        <SharedCaption board={board} />
        <ErrorBoundary label="Tidslinjen"><Timeline board={board} readOnly viewer /></ErrorBoundary>
      </div>
    </div>
  );
}
