"use client";

// The host's side of a lesson's chat: the chat so far and its settings when
// the session starts (or is picked up after a reload), and the host's own
// topic, where questions meant for the host alone arrive.
import type { RealtimeChannel, SupabaseClient } from "@supabase/supabase-js";
import { useEffect } from "react";
import type { ChatMessage } from "../../../lib/tactics/live-chat.ts";
import { listenChat, useChat } from "./chat-store.ts";
import { useLive } from "./live-store.ts";

export function useLiveHostChat(client: SupabaseClient | null, sessionId: string | undefined) {
  useEffect(() => {
    if (!client || !sessionId) return;
    let channel: RealtimeChannel | null = null;
    let disposed = false;
    const session = useLive.getState().session;
    useChat.getState().set({ messages: [], unread: 0, chatMode: session?.chat_mode ?? "on", hands: session?.hands ?? true });
    void (async () => {
      const [{ data: user }, { data: history }] = await Promise.all([
        client.auth.getUser(),
        client.schema("api").rpc("list_tactics_live_messages", { target_session_id: sessionId }),
      ]);
      if (disposed) return;
      useChat.getState().set({ selfId: user.user?.id ?? null });
      useChat.getState().add((history as ChatMessage[] | null) ?? []);
      useChat.getState().set({ unread: 0 });
      channel = client.channel(`tactics-live-host:${sessionId}`, { config: { private: true } });
      listenChat(channel);
      channel.subscribe();
    })();
    return () => {
      disposed = true;
      if (channel) void client.removeChannel(channel);
    };
  }, [client, sessionId]);
}
