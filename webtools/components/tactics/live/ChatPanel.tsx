"use client";

// A live lesson's chat: the messages so far, newest at the foot, and a line
// to write in. The host's messages stand out, a question meant for the
// host alone says so, and the host can remove any message. What the
// participant may write follows the host's settings.
import type { SupabaseClient } from "@supabase/supabase-js";
import { useEffect, useRef, useState } from "react";
import { chatError, clockTime, type ChatMessage } from "../../../lib/tactics/live-chat.ts";
import { useChat } from "./chat-store.ts";

export function ChatPanel({ client, sessionId, host }: { client: SupabaseClient; sessionId: string; host: boolean }) {
  const messages = useChat(state => state.messages);
  const chatMode = useChat(state => state.chatMode);
  const muted = useChat(state => state.muted);
  const selfId = useChat(state => state.selfId);
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const list = useRef<HTMLOListElement>(null);

  // In sight, nothing is unread; new messages scroll into view.
  useEffect(() => {
    useChat.getState().set({ open: true, unread: 0 });
    return () => useChat.getState().set({ open: false });
  }, []);
  useEffect(() => { list.current?.scrollTo({ top: list.current.scrollHeight }); }, [messages.length]);

  const canWrite = host || (chatMode !== "off" && !muted);
  const send = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!text.trim() || busy) return;
    setBusy(true); setError("");
    const { data, error: sendError } = await client.schema("api").rpc("send_tactics_live_message", { target_session_id: sessionId, message_body: text });
    setBusy(false);
    if (sendError) { setError(chatError(sendError.message)); return; }
    useChat.getState().add([data as ChatMessage]);
    setText("");
  };
  const remove = async (message: ChatMessage) => {
    if (!window.confirm("Ta bort meddelandet för alla?")) return;
    const { error: removeError } = await client.schema("api").rpc("delete_tactics_live_message", { target_message_id: message.id });
    if (removeError) setError("Meddelandet kunde inte tas bort."); else useChat.getState().remove(message.id);
  };

  const notice = host ? null
    : chatMode === "off" ? "Läraren har stängt av chatten."
    : muted ? "Läraren har stängt av chatten för dig."
    : chatMode === "questions" ? "Det du skriver går bara till läraren." : null;
  return (
    <section className="tb-chat" aria-label="Chatt">
      <ol ref={list} className="tb-chat-list">
        {messages.length === 0 && <li className="tb-chat-empty">Inga meddelanden än.</li>}
        {messages.map(message => (
          <li key={message.id} data-host={message.from_host} data-own={message.profile_id === selfId}>
            <div className="tb-chat-meta">
              <strong>{message.name}</strong>
              {message.to_host && <span className="tb-chat-tag">{host ? "Fråga" : "Bara till läraren"}</span>}
              <time>{clockTime(message.created_at)}</time>
              {host && <button type="button" className="tb-chat-remove" aria-label="Ta bort meddelandet" onClick={() => void remove(message)}>×</button>}
            </div>
            <p>{message.body}</p>
          </li>
        ))}
      </ol>
      {notice && <p className="tb-chat-notice">{notice}</p>}
      {canWrite && (
        <form className="tb-chat-form" onSubmit={send}>
          <input value={text} maxLength={500} onChange={event => setText(event.target.value)} aria-label="Meddelande"
            placeholder={host ? "Skriv till alla" : chatMode === "questions" ? "Fråga läraren" : "Skriv i chatten"} />
          <button type="submit" className="wt-button small" disabled={busy || !text.trim()}>Skicka</button>
        </form>
      )}
      {error && <p className="wt-error" role="alert">{error}</p>}
    </section>
  );
}
