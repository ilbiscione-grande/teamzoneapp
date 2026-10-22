"use client";

// A participant's live lesson: the board as the host shows it, with the
// host's pointer, the board's description beside it and where the lesson
// is (board, frame) under it. Nothing is changed or played here; the board
// follows the host.
import type { SupabaseClient } from "@supabase/supabase-js";
import dynamic from "next/dynamic";
import { useEffect, useMemo, useState } from "react";
import { normalizeDocument } from "../../../lib/tactics/document.ts";
import type { LiveJoined, LivePresence } from "../../../lib/tactics/live.ts";
import { BoardText, hasBoardText } from "../BoardText.tsx";
import { ErrorBoundary } from "../ErrorBoundary.tsx";
import { activeBoard, isBetween, useEditor, NONE } from "../store.ts";
import { usePlayback } from "../timeline/use-playback.ts";
import { kindLabels } from "../TopBar.tsx";
import { Laser } from "./Laser.tsx";
import { useLive } from "./live-store.ts";
import { useLiveFollow } from "./use-live-follow.ts";

const BoardStage = dynamic(() => import("../stage/BoardStage.tsx"), { ssr: false, loading: () => <div className="tb-stage" /> });

const ended = { ended: "Lektionen är slut. Tack för att du var med!", removed: "Läraren kräver nu inloggning. Logga in för att vara med igen.", failed: "Det gick inte att ansluta till lektionen. Ladda om sidan och försök igen." };

export function LiveViewer({ client, joined, guest }: { client: SupabaseClient; joined: LiveJoined; guest: boolean }) {
  const [ready, setReady] = useState(false);
  const [showText, setShowText] = useState(false);
  const me = useMemo<LivePresence>(() => ({ role: "participant", name: joined.participant_name, guest }), [joined.participant_name, guest]);
  useEffect(() => {
    const document = normalizeDocument(joined.document);
    useEditor.getState().load({
      id: joined.project_id, name: joined.name, kind: joined.kind, teamzone_team_id: null, team_name: null,
      board_count: document.boards.length, revision: 0, created_at: joined.created_at, updated_at: joined.created_at, document,
    }, document);
    setShowText(hasBoardText(useEditor.getState()));
    setReady(true);
  }, [joined]);
  const { state, detail } = useLiveFollow(client, joined.id, me);
  usePlayback();
  const board = useEditor(activeBoard);
  const boards = useEditor(store => store.document?.boards ?? NONE);
  const playhead = useEditor(store => store.playhead);
  const between = useEditor(isBetween);
  const hostHere = useLive(store => store.hostHere);

  if (state === "ended" || state === "removed" || state === "failed") {
    return (
      <div className="wt-wrap wt-section">
        <p className="wt-status" role="status">{ended[state]}</p>
        {state === "failed" && detail && <p className="wt-small">Felet från anslutningen: {detail}</p>}
      </div>
    );
  }
  if (!ready || !board) return null;
  const frame = Math.floor(playhead) + 1;
  const where = between ? `Mellan frame ${frame} och ${frame + 1}` : `Frame ${Math.round(playhead) + 1} av ${board.frames.length}`;
  return (
    <div className="tb-editor tb-viewer tb-live" data-text={showText}>
      <header className="tb-top">
        <div className="tb-top-row">
          <span className="tb-viewer-mark" aria-hidden="true">TZ</span>
          <div className="tb-viewer-title">
            <strong>{joined.name}</strong>
            <span>{kindLabels[joined.kind]} · live med {joined.host_name}</span>
          </div>
          <span className="tb-spacer" />
          <span className="tb-live-status" data-host={hostHere}>{state === "connecting" ? "Ansluter…" : hostHere ? "Följer läraren" : "Väntar på läraren"}</span>
          <button type="button" className="tb-present-toggle" aria-pressed={showText} onClick={() => setShowText(!showText)}>Beskrivning</button>
        </div>
      </header>
      <div className="tb-present-body">
        <div className="tb-center">
          <ErrorBoundary label="Tavlan"><BoardStage editable={false} extra={<Laser />} /></ErrorBoundary>
          <div className="tb-live-where" aria-live="polite">
            <strong>{board.name || "Tavla"}</strong>{boards.length > 1 && <span> · tavla {boards.findIndex(item => item.id === board.id) + 1} av {boards.length}</span>}
            {board.frames.length > 1 && <span> · {where}</span>}
          </div>
        </div>
        {showText && <BoardText emptyHint="Tavlan har ingen beskrivning." />}
      </div>
    </div>
  );
}
