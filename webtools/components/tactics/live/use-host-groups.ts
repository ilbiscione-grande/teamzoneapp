"use client";

// The host listens on every group's channel, so the overview's pictures of
// the groups' copies move as the groups move objects: on the way and where
// dropped. The database's moves come back whenever the list is read again.
import type { RealtimeChannel, SupabaseClient } from "@supabase/supabase-js";
import { useEffect } from "react";
import { groupTopic, mergeGroupMoves, type GroupMove } from "../../../lib/tactics/live-groups.ts";
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
        channel.on("broadcast", { event: "group-move" }, ({ payload }) => {
          const move = payload as GroupMove;
          const { groups, set } = useGroup.getState();
          set({ groups: groups.map(group => group.id === id ? { ...group, moves: mergeGroupMoves(group.moves, move.frameIndex, move.moves) } : group) });
        });
        channel.subscribe();
        channels.push(channel);
      }
    })();
    return () => { disposed = true; for (const channel of channels) void client.removeChannel(channel); };
  }, [client, ids]);
}
