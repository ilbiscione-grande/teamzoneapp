"use client";

// A participant given the floor: the objects they drag go to the host and
// everyone else, a few times a second on the way and once more where they
// are dropped (which the host's board takes in).
import type { SupabaseClient } from "@supabase/supabase-js";
import { useEffect } from "react";
import { throttle } from "../../../lib/tactics/live.ts";
import { objectDrag, objectDrop } from "../stage/stage-context.ts";
import { useEditor } from "../store.ts";
import { useDraw } from "./draw-store.ts";

type Moves = Record<string, { x: number; y: number }>;

export function useFloorMoves(client: SupabaseClient, sessionId: string, hasFloor: boolean) {
  useEffect(() => {
    if (!hasFloor) return;
    const send = (moves: Moves, dropped: boolean) => {
      const { boardId, frameIndex } = useEditor.getState();
      if (!boardId) return;
      void client.schema("api").rpc("move_tactics_live_floor", {
        target_session_id: sessionId, target_board_id: boardId, target_frame_index: frameIndex, object_moves: moves, dropped,
      }).then(({ error }) => {
        // Said under the board, so a move that did not reach the host is not silent.
        if (error) useDraw.getState().set({ error: `Flytten nådde inte läraren (${error.message}).` });
        else if (dropped) useDraw.getState().set({ error: "" });
      });
    };
    const onTheWay = throttle((moves: Moves) => send(moves, false), 150);
    const dropped = (moves: Moves) => { onTheWay.cancel(); send(moves, true); };
    objectDrag.add(onTheWay.call);
    objectDrop.add(dropped);
    return () => { objectDrag.delete(onTheWay.call); objectDrop.delete(dropped); onTheWay.cancel(); };
  }, [client, sessionId, hasFloor]);
}
