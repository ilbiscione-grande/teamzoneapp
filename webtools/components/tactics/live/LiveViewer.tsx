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
import { activeBoard, useEditor } from "../store.ts";
import { usePlayback } from "../timeline/use-playback.ts";
import { kindLabels } from "../TopBar.tsx";
import { useChat } from "./chat-store.ts";
import { ChatPanel } from "./ChatPanel.tsx";
import { useDraw } from "./draw-store.ts";
import { Laser } from "./Laser.tsx";
import { LiveStrokes } from "./LiveStrokes.tsx";
import { LiveAnswers } from "./LiveAnswers.tsx";
import { useQuestions } from "./question-store.ts";
import { LiveDrawButtons, LiveWhere } from "./LiveWhere.tsx";
import { useFloorMoves } from "./use-floor.ts";
import { LiveBadge } from "./LiveBadge.tsx";
import { useLive } from "./live-store.ts";
import { useLiveFollow } from "./use-live-follow.ts";

const BoardStage = dynamic(() => import("../stage/BoardStage.tsx"), { ssr: false, loading: () => <div className="tb-stage" /> });

const ended = { ended: "Lektionen är slut. Tack för att du var med!", removed: "Läraren kräver nu inloggning. Logga in för att vara med igen.", failed: "Det gick inte att ansluta till lektionen. Ladda om sidan och försök igen." };

export function LiveViewer({ client, joined, guest }: { client: SupabaseClient; joined: LiveJoined; guest: boolean }) {
  const [ready, setReady] = useState(false);
  const [aside, setAside] = useState<"text" | "chat" | null>(null);
  const me = useMemo<LivePresence>(() => ({ role: "participant", name: joined.participant_name, guest }), [joined.participant_name, guest]);
  useEffect(() => {
    const document = normalizeDocument(joined.document);
    useEditor.getState().load({
      id: joined.project_id, name: joined.name, kind: joined.kind, teamzone_team_id: null, team_name: null,
      board_count: document.boards.length, revision: 0, created_at: joined.created_at, updated_at: joined.created_at, document,
    }, document);
    useChat.getState().set({ messages: [], unread: 0, chatMode: joined.chat_mode, hands: joined.hands, muted: joined.muted });
    useQuestions.getState().set({ questions: [], error: "" });
    useDraw.getState().set({ strokes: [], own: [], pen: false, error: "", drawMode: joined.draw_mode, floorHolder: joined.floor_holder, floorName: joined.floor_name });
    setAside(hasBoardText(useEditor.getState()) ? "text" : null);
    setReady(true);
  }, [joined]);
  const { state, detail, hand, setHand } = useLiveFollow(client, joined.id, me);
  const chatMode = useChat(store => store.chatMode);
  const handsAllowed = useChat(store => store.hands);
  const hasMessages = useChat(store => store.messages.length > 0);
  const toggle = (which: "text" | "chat") => setAside(aside === which ? null : which);
  usePlayback();
  const board = useEditor(activeBoard);
  const hostHere = useLive(store => store.hostHere);
  const selfId = useChat(store => store.selfId);
  const hasFloor = useDraw(store => !!store.floorHolder && store.floorHolder === selfId);
  useFloorMoves(client, joined.id, hasFloor);

  if (state === "ended" || state === "removed" || state === "failed") {
    return (
      <div className="wt-wrap wt-section">
        <p className="wt-status" role="status">{ended[state]}</p>
        {state === "failed" && detail && <p className="wt-small">Felet från anslutningen: {detail}</p>}
      </div>
    );
  }
  if (!ready || !board) return null;
  return (
    <div className="tb-editor tb-viewer tb-live" data-text={aside !== null}>
      <header className="tb-top">
        <div className="tb-top-row">
          <span className="tb-viewer-mark" aria-hidden="true">TZ</span>
          <div className="tb-viewer-title">
            <strong>{joined.name}</strong>
            <span>{kindLabels[joined.kind]} · live med {joined.host_name}</span>
          </div>
          <span className="tb-spacer" />
          {/* On a phone the row scrolls sideways rather than lose a button. */}
          <div className="tb-live-actions">
            <span className="tb-live-status" data-host={hostHere}>{state === "connecting" ? "Ansluter…" : hostHere ? "Följer läraren" : "Väntar på läraren"}</span>
            {handsAllowed && state === "following" && (
              <button type="button" className="tb-present-toggle" aria-pressed={!!hand} onClick={() => setHand(!hand)} title={hand ? "Sänk handen" : "Räck upp handen"}>✋</button>
            )}
            {(chatMode !== "off" || hasMessages) && (
              <button type="button" className="tb-present-toggle" aria-pressed={aside === "chat"} onClick={() => toggle("chat")}><LiveBadge label="Chatt" /></button>
            )}
            {state === "following" && <LiveDrawButtons />}
            <button type="button" className="tb-present-toggle" aria-pressed={aside === "text"} onClick={() => toggle("text")}>Beskrivning</button>
          </div>
        </div>
      </header>
      <div className="tb-present-body">
        <div className="tb-center">
          <ErrorBoundary label="Tavlan">
            <BoardStage editable={hasFloor} moveOnly
              extra={<><LiveStrokes pen={selfId ? { client, sessionId: joined.id, selfId } : undefined} /><LiveAnswers answering={{ client }} /><Laser /></>} />
          </ErrorBoundary>
          <LiveWhere hasFloor={hasFloor} />
        </div>
        {aside === "text" && <BoardText emptyHint="Tavlan har ingen beskrivning." />}
        {aside === "chat" && <aside className="tb-present-text tb-present-live"><ChatPanel client={client} sessionId={joined.id} host={false} /></aside>}
      </div>
    </div>
  );
}
