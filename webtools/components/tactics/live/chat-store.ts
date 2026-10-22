"use client";

// A live lesson's chat in this browser: the messages, the chat's mode and
// whether hands may be raised, and for a participant whether their chat is
// off and their hand is up. The channel's chat events feed it.
import type { RealtimeChannel } from "@supabase/supabase-js";
import { create } from "zustand";
import { mergeMessages, type ChatMessage, type ChatMode } from "../../../lib/tactics/live-chat.ts";

type ChatState = {
  messages: ChatMessage[];
  chatMode: ChatMode;
  hands: boolean;
  /** This browser's own account, so its messages are not counted as unread. */
  selfId: string | null;
  /** Participating: whether the host turned this participant's chat off. */
  muted: boolean;
  /** Messages from others while the chat is not in sight. */
  unread: number;
  open: boolean;
  add: (incoming: ChatMessage[]) => void;
  remove: (id: string) => void;
  set: (changes: Partial<Omit<ChatState, "add" | "remove" | "set">>) => void;
};

export const useChat = create<ChatState>((set, get) => ({
  messages: [],
  chatMode: "on",
  hands: true,
  selfId: null,
  muted: false,
  unread: 0,
  open: false,
  add: incoming => {
    const { messages, open, selfId, unread } = get();
    const fresh = incoming.filter(message => !messages.some(known => known.id === message.id) && message.profile_id !== selfId);
    set({ messages: mergeMessages(messages, incoming), unread: open ? 0 : unread + fresh.length });
  },
  remove: id => set(state => ({ messages: state.messages.filter(message => message.id !== id) })),
  set: changes => set(changes),
}));

/**
 * The chat's events on a lesson's channel: messages and removals sent by
 * the database, and the host's settings. For a participant, also the host
 * turning their chat off or lowering their hand.
 */
export function listenChat(channel: RealtimeChannel, participant?: { id: string; onLowerHand: () => void }) {
  channel
    .on("broadcast", { event: "chat" }, ({ payload }) => useChat.getState().add([payload as ChatMessage]))
    .on("broadcast", { event: "chat-deleted" }, ({ payload }) => useChat.getState().remove((payload as { id: string }).id))
    .on("broadcast", { event: "settings" }, ({ payload }) => {
      const { chatMode, hands } = payload as { chatMode: ChatMode; hands: boolean };
      useChat.getState().set({ chatMode, hands });
      if (!hands) participant?.onLowerHand();
    });
  if (!participant) return;
  channel
    .on("broadcast", { event: "muted" }, ({ payload }) => {
      const { profileId, muted } = payload as { profileId: string; muted: boolean };
      if (profileId === participant.id) useChat.getState().set({ muted });
    })
    .on("broadcast", { event: "lower-hand" }, ({ payload }) => {
      if ((payload as { key: string }).key === participant.id) participant.onLowerHand();
    });
}
