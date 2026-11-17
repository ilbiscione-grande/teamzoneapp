"use client";

// A group's own chat: what the group's members write to each other while
// they work, beside the class's chat. For the host (following a group) it is
// read only. It goes with the group when the group work ends.
import type { SupabaseClient } from "@supabase/supabase-js";
import { useEffect, useRef, useState } from "react";
import { clockTime, mergeMessages, type ChatMessage } from "../../../lib/tactics/live-chat.ts";
import { groupError } from "../../../lib/tactics/live-groups.ts";
import { useLanguage } from "../../language";
import { useChat } from "./chat-store.ts";
import { useGroup } from "./group-store.ts";

export function GroupChat({ messages, number, writing }: {
  messages: ChatMessage[]; number: number; writing?: { client: SupabaseClient; sessionId: string };
}) {
  const { t, intl } = useLanguage();
  const selfId = useChat(state => state.selfId);
  const muted = useChat(state => state.muted);
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const list = useRef<HTMLOListElement>(null);
  useEffect(() => { list.current?.scrollTo({ top: list.current.scrollHeight }); }, [messages.length]);

  const send = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!writing || !text.trim() || busy) return;
    setBusy(true); setError("");
    const { data, error: sendError } = await writing.client.schema("api").rpc("send_tactics_live_group_message", { target_session_id: writing.sessionId, message_body: text });
    setBusy(false);
    if (sendError) { setError(t(groupError(sendError.message))); return; }
    const { group } = useGroup.getState();
    if (group) useGroup.getState().set({ group: { ...group, messages: mergeMessages(group.messages, [data as ChatMessage]) } });
    setText("");
  };

  return (
    <section className="tb-chat tb-group-chat" aria-label={t("Chatt i grupp {number}", { number })}>
      <h3>{t("Chatt i grupp {number}", { number })}</h3>
      <ol ref={list} className="tb-chat-list">
        {messages.length === 0 && <li className="tb-chat-empty">{writing ? t("Bara gruppen ser det som skrivs här.") : t("Inga meddelanden än.")}</li>}
        {messages.map(message => (
          <li key={message.id} data-own={message.profile_id === selfId}>
            <div className="tb-chat-meta"><strong>{message.name}</strong><time>{clockTime(message.created_at, intl)}</time></div>
            <p>{message.body}</p>
          </li>
        ))}
      </ol>
      {writing && muted && <p className="tb-chat-notice">{t("Läraren har stängt av chatten för dig.")}</p>}
      {writing && !muted && (
        <form className="tb-chat-form" onSubmit={send}>
          <input value={text} maxLength={500} onChange={event => setText(event.target.value)} aria-label={t("Meddelande till gruppen")} placeholder={t("Skriv till gruppen")} />
          <button type="submit" className="wt-button small" disabled={busy || !text.trim()}>{t("Skicka")}</button>
        </form>
      )}
      {error && <p className="wt-error" role="alert">{error}</p>}
    </section>
  );
}
