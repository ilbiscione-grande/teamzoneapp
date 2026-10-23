"use client";

// Running a live lesson, for the host: the chat's mode, whether hands may
// be raised and how participants may draw (with clearing the shared
// drawings), the hands in the order they went up (lowered with a click),
// who is in (LivePeople) and the chat itself. In the editor's side panel,
// and beside the board when presenting.
import { useState } from "react";
import { chatModeLabels, raisedHands, type ChatMode } from "../../../lib/tactics/live-chat.ts";
import { drawModeLabels, type DrawMode } from "../../../lib/tactics/live-draw.ts";
import type { LiveSession } from "../../../lib/tactics/live.ts";
import { useAccount } from "../../account";
import { useEditor } from "../store.ts";
import { useChat } from "./chat-store.ts";
import { ChatPanel } from "./ChatPanel.tsx";
import { useDraw } from "./draw-store.ts";
import { HostNotes } from "./HostNotes.tsx";
import { LivePeople } from "./LivePeople.tsx";
import { LiveQuestion } from "./LiveQuestion.tsx";
import { useLive } from "./live-store.ts";

export function LivePanel() {
  const { client } = useAccount();
  const session = useLive(state => state.session);
  const participants = useLive(state => state.participants);
  const chatMode = useChat(state => state.chatMode);
  const hands = useChat(state => state.hands);
  const drawMode = useDraw(state => state.drawMode);
  const strokeCount = useDraw(state => state.strokes.length);
  const [error, setError] = useState("");
  if (!client || !session) return null;
  const send = (event: string, payload: object) => useLive.getState().send?.(event, payload);
  const saved = (data: unknown) => useLive.getState().set({ session: data as LiveSession });

  const chatSettings = async (mode: ChatMode, handsAllowed: boolean) => {
    setError("");
    const { data, error: saveError } = await client.schema("api").rpc("set_tactics_live_chat", { target_session_id: session.id, new_chat_mode: mode, hands_allowed: handsAllowed });
    if (saveError) { setError("Inställningen kunde inte sparas."); return; }
    saved(data);
    useChat.getState().set({ chatMode: mode, hands: handsAllowed });
    send("settings", { chatMode: mode, hands: handsAllowed, drawMode });
  };
  const drawSettings = async (mode: DrawMode) => {
    setError("");
    const { data, error: saveError } = await client.schema("api").rpc("set_tactics_live_drawing", { target_session_id: session.id, new_draw_mode: mode });
    if (saveError) { setError("Inställningen kunde inte sparas."); return; }
    saved(data);
    useDraw.getState().set({ drawMode: mode });
    send("settings", { chatMode, hands, drawMode: mode });
  };
  const clear = async () => {
    if (!window.confirm("Rensa allas ritningar på den här tavlan?")) return;
    const { error: clearError } = await client.schema("api").rpc("clear_tactics_live_strokes", { target_session_id: session.id, target_board_id: useEditor.getState().boardId });
    if (clearError) setError("Ritningarna kunde inte rensas.");
  };
  const up = raisedHands(participants);

  return (
    <div className="tb-inspector tb-live-panel">
      <h3>Livelektion · {session.code}</h3>
      <HostNotes />
      <div className="tb-row">
        <label className="tb-field">Chatt
          <select value={chatMode} onChange={event => void chatSettings(event.target.value as ChatMode, hands)}>
            {(Object.keys(chatModeLabels) as ChatMode[]).map(mode => <option key={mode} value={mode}>{chatModeLabels[mode]}</option>)}
          </select>
        </label>
        <label className="tb-field">Eleverna ritar
          <select value={drawMode} onChange={event => void drawSettings(event.target.value as DrawMode)}>
            {(Object.keys(drawModeLabels) as DrawMode[]).map(mode => <option key={mode} value={mode}>{drawModeLabels[mode]}</option>)}
          </select>
        </label>
      </div>
      <label className="tb-check"><input type="checkbox" checked={hands} onChange={event => void chatSettings(chatMode, event.target.checked)} />Deltagarna kan räcka upp handen</label>
      {strokeCount > 0 && <button type="button" className="tb-link" onClick={() => void clear()}>Rensa allas ritningar på tavlan</button>}
      {hands && up.length > 0 && (
        <>
          <h3>✋ Räcker upp handen ({up.length})</h3>
          <ol className="tb-live-hands">
            {up.map(person => (
              <li key={person.key}><span>{person.name}</span><button type="button" className="tb-link" onClick={() => send("lower-hand", { key: person.key })}>Sänk</button></li>
            ))}
          </ol>
        </>
      )}
      <h3>Fråga på planen</h3>
      <LiveQuestion client={client} sessionId={session.id} />
      <h3>Med nu ({participants.length})</h3>
      <LivePeople client={client} session={session} onError={setError} />
      {error && <p className="wt-error" role="alert">{error}</p>}
      <h3>Chatt</h3>
      <ChatPanel client={client} sessionId={session.id} host />
    </div>
  );
}
