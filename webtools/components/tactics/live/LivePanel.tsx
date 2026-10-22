"use client";

// Running a live lesson, for the host: the chat's mode and whether hands
// may be raised, the hands in the order they went up (lowered with a
// click), who is in with their chat on or off, and the chat itself. In the
// editor's side panel, and beside the board when presenting.
import { useState } from "react";
import { chatModeLabels, raisedHands, type ChatMode } from "../../../lib/tactics/live-chat.ts";
import type { LiveSession } from "../../../lib/tactics/live.ts";
import { useAccount } from "../../account";
import { useChat } from "./chat-store.ts";
import { ChatPanel } from "./ChatPanel.tsx";
import { useLive } from "./live-store.ts";

export function LivePanel() {
  const { client } = useAccount();
  const session = useLive(state => state.session);
  const participants = useLive(state => state.participants);
  const chatMode = useChat(state => state.chatMode);
  const hands = useChat(state => state.hands);
  const [error, setError] = useState("");
  if (!client || !session) return null;
  const send = (event: string, payload: object) => useLive.getState().send?.(event, payload);

  const settings = async (mode: ChatMode, handsAllowed: boolean) => {
    setError("");
    const { data, error: saveError } = await client.schema("api").rpc("set_tactics_live_chat", { target_session_id: session.id, new_chat_mode: mode, hands_allowed: handsAllowed });
    if (saveError) { setError("Inställningen kunde inte sparas."); return; }
    useLive.getState().set({ session: data as LiveSession });
    useChat.getState().set({ chatMode: mode, hands: handsAllowed });
    send("settings", { chatMode: mode, hands: handsAllowed });
  };
  const mute = async (key: string, muted: boolean) => {
    const { error: muteError } = await client.schema("api").rpc("mute_tactics_live_participant", { target_session_id: session.id, target_profile_id: key, is_muted: muted });
    if (muteError) { setError("Det gick inte att ändra deltagarens chatt."); return; }
    send("muted", { profileId: key, muted });
  };
  const up = raisedHands(participants);

  return (
    <div className="tb-inspector tb-live-panel">
      <h3>Livelektion · {session.code}</h3>
      <div className="tb-row">
        <label className="tb-field">Chatt
          <select value={chatMode} onChange={event => void settings(event.target.value as ChatMode, hands)}>
            {(Object.keys(chatModeLabels) as ChatMode[]).map(mode => <option key={mode} value={mode}>{chatModeLabels[mode]}</option>)}
          </select>
        </label>
      </div>
      <label className="tb-check"><input type="checkbox" checked={hands} onChange={event => void settings(chatMode, event.target.checked)} />Deltagarna kan räcka upp handen</label>
      {hands && up.length > 0 && (
        <>
          <h3>✋ Räcker upp handen ({up.length})</h3>
          <ol className="tb-live-hands">
            {up.map(person => (
              <li key={person.key}>{person.name}<button type="button" className="tb-link" onClick={() => send("lower-hand", { key: person.key })}>Sänk</button></li>
            ))}
          </ol>
        </>
      )}
      <h3>Med nu ({participants.length})</h3>
      {participants.length === 0 ? <p className="tb-hint">Ingen än.</p> : (
        <ul className="tb-live-people tb-live-people-list">
          {participants.map(person => (
            <li key={person.key}>
              <span>{person.hand ? "✋ " : ""}{person.name}{person.guest && <small> gäst</small>}</span>
              <button type="button" className="tb-link" onClick={() => void mute(person.key, !person.muted)}>{person.muted ? "Slå på chatten" : "Stäng av chatten"}</button>
            </li>
          ))}
        </ul>
      )}
      {error && <p className="wt-error" role="alert">{error}</p>}
      <h3>Chatt</h3>
      <ChatPanel client={client} sessionId={session.id} host />
    </div>
  );
}
