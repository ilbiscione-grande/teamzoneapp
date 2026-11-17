"use client";

// The host listens on every group's channel, so the overview's pictures of
// the groups' copies move as the groups move objects: on the way and where
// dropped, what they place, change and remove, and what the groups draw
// and write in their chats. The
// database's copies come back whenever the list is read again.
import type { RealtimeChannel, SupabaseClient } from "@supabase/supabase-js";
import { useEffect } from "react";
import { mergeMessages, type ChatMessage } from "../../../lib/tactics/live-chat.ts";
import { mergeGroupEdits, type FrameEdit } from "../../../lib/tactics/live-group-edits.ts";
import { mergeStrokes, type Stroke } from "../../../lib/tactics/live-draw.ts";
import { groupTopic, mergeGroupMoves, type GroupMove, type HostGroup } from "../../../lib/tactics/live-groups.ts";
import { useGroup } from "./group-store.ts";

export function useHostGroups(client: SupabaseClient) {
  // The same groups keep their channels when only their copies or members change.
  const ids = useGroup(store => store.groups.map(group => group.id).join(","));
  useEffect(() => {
    if (!ids) return;
    const channels: RealtimeChannel[] = [];
    let disposed = false;
    void (async () => {
      await client.realtime.setAuth();
      if (disposed) return;
      for (const id of ids.split(",")) {
        const channel = client.channel(groupTopic(id), { config: { private: true } });
        const change = (next: (group: HostGroup) => HostGroup) => {
          const { groups, set } = useGroup.getState();
          set({ groups: groups.map(group => group.id === id ? next(group) : group) });
        };
        channel.on("broadcast", { event: "group-move" }, ({ payload }) => {
          const move = payload as GroupMove;
          change(group => ({ ...group, moves: mergeGroupMoves(group.moves, move.frameIndex, move.moves) }));
        });
        channel.on("broadcast", { event: "group-edit" }, ({ payload }) => change(group => ({ ...group, edits: mergeGroupEdits(group.edits, payload as FrameEdit) })));
        channel.on("broadcast", { event: "group-stroke" }, ({ payload }) => change(group => ({ ...group, strokes: mergeStrokes(group.strokes, [payload as Stroke]) })));
        channel.on("broadcast", { event: "group-chat" }, ({ payload }) => change(group => ({ ...group, messages: mergeMessages(group.messages, [payload as ChatMessage]) })));
        channel.subscribe();
        channels.push(channel);
      }
    })();
    return () => { disposed = true; for (const channel of channels) void client.removeChannel(channel); };
  }, [client, ids]);
}
