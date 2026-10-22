"use client";

// A shared link's page: the boards to watch and play, nothing to change.
// The board and its timeline are the editor's own, read-only.
import dynamic from "next/dynamic";
import { useEffect, useState } from "react";
import { normalizeDocument } from "../../lib/tactics/document.ts";
import type { SharedTactics } from "../../lib/tactics/shared.ts";
import { ErrorBoundary } from "./ErrorBoundary.tsx";
import { BigQr } from "./QrCode.tsx";
import { Presenter } from "./Presenter.tsx";
import { activeBoard, useEditor, NONE } from "./store.ts";
import { Timeline } from "./timeline/Timeline.tsx";
import { kindLabels } from "./TopBar.tsx";
import "./tactics.css";

const BoardStage = dynamic(() => import("./stage/BoardStage.tsx"), { ssr: false, loading: () => <div className="tb-stage" /> });

export function SharedViewer({ shared }: { shared: SharedTactics }) {
  const [ready, setReady] = useState(false);
  const [qr, setQr] = useState(false);
  const [presenting, setPresenting] = useState(false);
  const board = useEditor(activeBoard);
  const boards = useEditor(state => state.document?.boards ?? NONE);
  const boardId = useEditor(state => state.boardId);
  useEffect(() => {
    const document = normalizeDocument({ boards: shared.boards });
    useEditor.getState().load({
      id: "shared", name: shared.name, kind: shared.kind, teamzone_team_id: null, team_name: shared.team_name,
      board_count: document.boards.length, revision: 0, created_at: shared.updated_at, updated_at: shared.updated_at, document,
    }, document);
    setReady(true);
  }, [shared]);
  if (!ready || !board) return null;
  if (presenting) return <div className="tb-viewer"><Presenter onClose={() => setPresenting(false)} /></div>;
  return (
    <div className="tb-editor tb-viewer">
      <header className="tb-top">
        <div className="tb-top-row">
          <span className="tb-viewer-mark" aria-hidden="true">TZ</span>
          <div className="tb-viewer-title">
            <strong>{shared.name}</strong>
            <span>{[kindLabels[shared.kind], shared.team_name].filter(Boolean).join(" · ")}</span>
          </div>
          <span className="tb-spacer" />
          <button type="button" className="tb-icon tb-pdf" onClick={() => setPresenting(true)} aria-label="Visa i helskärm" title="Visa i helskärm med beskrivning">⛶</button>
          <button type="button" className="tb-icon tb-pdf" onClick={() => setQr(true)} title="Visa länken som QR-kod">QR</button>
        </div>
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
        <ErrorBoundary label="Tavlan"><BoardStage editable={false} /></ErrorBoundary>
        <ErrorBoundary label="Tidslinjen"><Timeline board={board} readOnly /></ErrorBoundary>
      </div>
    </div>
  );
}
