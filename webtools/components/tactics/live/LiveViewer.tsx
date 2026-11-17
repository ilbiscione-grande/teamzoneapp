"use client";

// A participant's live lesson: the board as the host shows it, with the
// host's pointer, the board's description beside it and where the lesson
// is (board, frame) under it. Nothing is changed or played here; the board
// follows the host. In group work the board is the group's own copy, and
// everyone in the group edits it with the editor's own tools, draws on it
// and has a chat of the group's own.
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
import { useGroup, worksOnOwn } from "./group-store.ts";
import { GroupChat } from "./GroupChat.tsx";
import { GroupStrokes } from "./GroupStrokes.tsx";
import { useGroupEdits } from "./use-group-edits.ts";
import { Toolbar } from "../panels/Toolbar.tsx";
import { PhoneToolbar } from "../panels/PhoneToolbar.tsx";
import { usePhone } from "../ViewerTools.tsx";
import { useLiveGroup } from "./use-live-group.ts";
import { LiveBadge } from "./LiveBadge.tsx";
import { useLive } from "./live-store.ts";
import { useLiveFollow } from "./use-live-follow.ts";
import { useT } from "../../language";

const BoardStage = dynamic(() => import("../stage/BoardStage.tsx"), { ssr: false, loading: () => <div className="tb-stage" /> });

const ended = {
  ended: "Lektionen är slut. Tack för att du var med!",
  removed: "Läraren kräver nu inloggning. Logga in för att vara med igen.",
  failed: "Det gick inte att ansluta till lektionen. Ladda om sidan och försök igen.",
};

export function LiveViewer({ client, joined, guest }: { client: SupabaseClient; joined: LiveJoined; guest: boolean }) {
  const t = useT();
  const [ready, setReady] = useState(false);
  const [chosenAside, setAside] = useState<"text" | "chat" | "group" | null>(null);
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
    useGroup.getState().set({ group: null, shown: null, hostBoard: null, pendingBoards: {}, pendingView: null, deadline: null });
    setAside(hasBoardText(useEditor.getState()) ? "text" : null);
    setReady(true);
  }, [joined]);
  const { state, detail, hand, setHand } = useLiveFollow(client, joined.id, me);
  const chatMode = useChat(store => store.chatMode);
  const handsAllowed = useChat(store => store.hands);
  const hasMessages = useChat(store => store.messages.length > 0);
  const toggle = (which: "text" | "chat" | "group") => setAside(aside === which ? null : which);
  usePlayback();
  const board = useEditor(activeBoard);
  const hostHere = useLive(store => store.hostHere);
  const selfId = useChat(store => store.selfId);
  const hasFloor = useDraw(store => !!store.floorHolder && store.floorHolder === selfId);
  const groupNumber = useGroup(store => store.group?.number ?? null);
  const grouped = groupNumber !== null;
  // While the host shows another group to everyone, that group's copy is only watched.
  const ownCopy = useGroup(worksOnOwn);
  const shownNumber = useGroup(store => grouped && !ownCopy ? store.shown?.number ?? null : null);
  useFloorMoves(client, joined.id, grouped ? (ownCopy ? "group" : null) : hasFloor ? "floor" : null);
  useLiveGroup(client, joined.id);
  const groupMessages = useGroup(store => store.group?.messages ?? null);
  const pen = useDraw(store => store.pen);
  // One's own group's copy is edited in full; the floor only moves objects on the host's board.
  const editing = grouped && ownCopy;
  useGroupEdits(client, joined.id, editing);
  const phone = usePhone();
  // The group's chat closes with the group work.
  const aside = chosenAside === "group" && !grouped ? null : chosenAside;

  if (state === "ended" || state === "removed" || state === "failed") {
    return (
      <div className="wt-wrap wt-section">
        <p className="wt-status" role="status">{t(ended[state])}</p>
        {state === "failed" && detail && <p className="wt-small">{t("Felet från anslutningen: {detail}", { detail })}</p>}
      </div>
    );
  }
  if (!ready || !board) return null;
  return (
    <div className="tb-editor tb-viewer tb-live" data-text={aside !== null} data-tools={editing && !phone}>
      <header className="tb-top">
        <div className="tb-top-row">
          <span className="tb-viewer-mark" aria-hidden="true">TZ</span>
          <div className="tb-viewer-title">
            <strong>{joined.name}</strong>
            <span>{t("{kind} · live med {name}", { kind: t(kindLabels[joined.kind]), name: joined.host_name })}</span>
          </div>
          <span className="tb-spacer" />
          {/* On a phone the row scrolls sideways rather than lose a button. */}
          <div className="tb-live-actions">
            <span className="tb-live-status" data-host={hostHere} data-group={grouped}>{state === "connecting" ? t("Ansluter…") : shownNumber !== null ? t("Grupp {number} visas", { number: shownNumber }) : grouped ? t("Grupp {number}", { number: groupNumber }) : hostHere ? t("Följer läraren") : t("Väntar på läraren")}</span>
            {handsAllowed && state === "following" && (
              <button type="button" className="tb-present-toggle" aria-pressed={!!hand} onClick={() => setHand(!hand)} title={hand ? t("Sänk handen") : t("Räck upp handen")}>✋</button>
            )}
            {(chatMode !== "off" || hasMessages) && (
              <button type="button" className="tb-present-toggle" aria-pressed={aside === "chat"} onClick={() => toggle("chat")}><LiveBadge label={t("Chatt")} /></button>
            )}
            {state === "following" && !grouped && <LiveDrawButtons />}
            {grouped && (
              <button type="button" className="tb-present-toggle" aria-pressed={aside === "group"} onClick={() => toggle("group")}>{t("Gruppens chatt")}</button>
            )}
            {grouped && ownCopy && (
              <button type="button" className="tb-present-toggle" aria-pressed={pen} onClick={() => useDraw.getState().set({ pen: !pen, error: "" })}
                title={t("Rita på gruppens kopia, gruppen ser det")}>{t("✏️ Rita")}</button>
            )}
            <button type="button" className="tb-present-toggle" aria-pressed={aside === "text"} onClick={() => toggle("text")}>{t("Beskrivning")}</button>
          </div>
        </div>
      </header>
      <div className="tb-present-body">
        {editing && !phone && <Toolbar homeColor={board.teams.home.color} awayColor={board.teams.away.color} />}
        <div className="tb-center">
          <ErrorBoundary label={t("Tavlan")}>
            {/* In a group, the class's drawings, answers and the host's pointer are not on the group's copy. */}
            <BoardStage editable={grouped ? ownCopy : hasFloor} moveOnly={!editing}
              phoneTools={editing && phone ? <PhoneToolbar homeColor={board.teams.home.color} awayColor={board.teams.away.color} /> : undefined}
              extra={grouped ? <GroupStrokes client={client} sessionId={joined.id} selfId={selfId} /> : <><LiveStrokes pen={selfId ? { client, sessionId: joined.id, selfId } : undefined} /><LiveAnswers answering={{ client }} /><Laser /></>} />
          </ErrorBoundary>
          <LiveWhere hasFloor={hasFloor} />
        </div>
        {aside === "text" && <BoardText emptyHint={t("Tavlan har ingen beskrivning.")} />}
        {aside === "group" && groupMessages && groupNumber !== null && (
          <aside className="tb-present-text tb-present-live"><GroupChat messages={groupMessages} number={groupNumber} writing={{ client, sessionId: joined.id }} /></aside>
        )}
        {aside === "chat" && <aside className="tb-present-text tb-present-live"><ChatPanel client={client} sessionId={joined.id} host={false} /></aside>}
      </div>
    </div>
  );
}
