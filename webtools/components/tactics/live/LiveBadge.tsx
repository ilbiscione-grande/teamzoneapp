"use client";

// A button's label with what waits in the lesson: unread messages, and for
// the host raised hands.
import { raisedHands } from "../../../lib/tactics/live-chat.ts";
import { useChat } from "./chat-store.ts";
import { useLive } from "./live-store.ts";
import { useT } from "../../language";

export function LiveBadge({ label, hands = false }: { label: string; hands?: boolean }) {
  const t = useT();
  const unread = useChat(state => state.unread);
  const up = useLive(state => hands ? raisedHands(state.participants).length : 0);
  return (
    <>
      {label}
      {up > 0 && <span className="tb-badge" aria-label={t("{count} räcker upp handen", { count: up })}>✋{up}</span>}
      {unread > 0 && <span className="tb-badge" aria-label={t("{count} olästa", { count: unread })}>{unread}</span>}
    </>
  );
}
