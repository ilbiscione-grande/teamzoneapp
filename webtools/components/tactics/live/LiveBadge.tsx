"use client";

// A button's label with what waits in the lesson: unread messages, and for
// the host raised hands.
import { raisedHands } from "../../../lib/tactics/live-chat.ts";
import { useChat } from "./chat-store.ts";
import { useLive } from "./live-store.ts";

export function LiveBadge({ label, hands = false }: { label: string; hands?: boolean }) {
  const unread = useChat(state => state.unread);
  const up = useLive(state => hands ? raisedHands(state.participants).length : 0);
  return (
    <>
      {label}
      {up > 0 && <span className="tb-badge" aria-label={`${up} räcker upp handen`}>✋{up}</span>}
      {unread > 0 && <span className="tb-badge" aria-label={`${unread} olästa`}>{unread}</span>}
    </>
  );
}
