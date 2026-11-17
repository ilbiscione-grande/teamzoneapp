"use client";

// A participant in a group listens to the group's channel: what the others
// in the group move shows on the group's copy, on the way and where dropped,
// and what they draw and write in the group's chat comes in.
// Once the channel is open the group is read again, so moves made before it
// opened are not missed.
import type { RealtimeChannel, SupabaseClient } from "@supabase/supabase-js";
import { useEffect } from "react";
import { mergeMessages, type ChatMessage } from "../../../lib/tactics/live-chat.ts";
import { mergeStrokes, type Stroke } from "../../../lib/tactics/live-draw.ts";
import { groupTopic, mergeGroupMoves } from "../../../lib/tactics/live-groups.ts";
import { applyMoves } from "../../../lib/tactics/live.ts";
import { useEditor } from "../store.ts";
import { useChat } from "./chat-store.ts";
import { displayedGroup, enterGroup, useGroup } from "./group-store.ts";
import type { GroupMove, LiveGroup } from "../../../lib/tactics/live-groups.ts";

export function useLiveGroup(client: SupabaseClient, sessionId: string) {
  const groupId = useGroup(store => store.group?.id ?? null);
  useEffect(() => {
    if (!groupId) return;
    let channel: RealtimeChannel | null = null;
    let disposed = false;
    void (async () => {
      await client.realtime.setAuth();
      if (disposed) return;
      channel = client.channel(groupTopic(groupId), { config: { private: true } });
      channel.on("broadcast", { event: "group-move" }, ({ payload }) => {
        const move = payload as GroupMove;
        const { group } = useGroup.getState();
        if (!group || group.id !== groupId) return;
        if (move.dropped) useGroup.getState().set({ group: { ...group, moves: mergeGroupMoves(group.moves, move.frameIndex, move.moves) } });
        // This participant's own move is still under their finger; another group shown to everyone is on the board meanwhile.
        if (move.by === useChat.getState().selfId || displayedGroup(useGroup.getState())?.id !== groupId) return;
        const { document } = useEditor.getState();
        if (document) useEditor.setState({ document: applyMoves(document, move) });
      });
      channel.on("broadcast", { event: "group-stroke" }, ({ payload }) => {
        const { group } = useGroup.getState();
        if (group?.id === groupId) useGroup.getState().set({ group: { ...group, strokes: mergeStrokes(group.strokes, [payload as Stroke]) } });
      });
      channel.on("broadcast", { event: "group-chat" }, ({ payload }) => {
        const { group } = useGroup.getState();
        if (group?.id === groupId) useGroup.getState().set({ group: { ...group, messages: mergeMessages(group.messages, [payload as ChatMessage]) } });
      });
      channel.subscribe(async status => {
        if (status !== "SUBSCRIBED") return;
        const { data } = await client.schema("api").rpc("get_tactics_live_group", { target_session_id: sessionId });
        const group = data as LiveGroup | null;
        if (group && group.id === groupId && useGroup.getState().group?.id === groupId) enterGroup(group);
      });
    })();
    return () => { disposed = true; if (channel) void client.removeChannel(channel); };
  }, [client, sessionId, groupId]);
}
