"use client";

// Following a live lesson: the session's channel is listened to and the
// board follows the host. A view moves the board, frame and playhead (a
// playing board is played on here from where the host was); a board
// replaces the participant's copy; a drag moves objects on the way; the
// pointer shows where the host points.
import type { RealtimeChannel, SupabaseClient } from "@supabase/supabase-js";
import { useEffect, useState } from "react";
import { applyBoard, applyMoves, liveTopic, type LiveDrag, type LivePresence, type LiveView } from "../../../lib/tactics/live.ts";
import type { Board, Point } from "../../../lib/tactics/model.ts";
import { useEditor } from "../store.ts";
import { useLive } from "./live-store.ts";

export type FollowState = "connecting" | "following" | "ended" | "removed" | "failed";

function applyView(view: LiveView) {
  const state = useEditor.getState();
  if (!state.document?.boards.some(board => board.id === view.boardId)) return;
  const common = { boardId: view.boardId, speed: view.speed, loop: view.loop, stopAt: null, selection: [] };
  if (view.playing) {
    useEditor.setState({ ...common, playing: true, playhead: view.playhead, frameIndex: Math.round(view.playhead), playSeq: state.playSeq + 1 });
  } else {
    useEditor.setState({ ...common, playing: false, playhead: view.playhead, frameIndex: view.frameIndex });
  }
}

function applyBoardFromHost(board: Board) {
  const { document } = useEditor.getState();
  if (document) useEditor.setState({ document: applyBoard(document, board) });
}

/** The follow state, and when the channel could not be opened, Realtime's own reason. */
export function useLiveFollow(client: SupabaseClient, sessionId: string, me: LivePresence): { state: FollowState; detail: string } {
  const [state, setState] = useState<FollowState>("connecting");
  const [detail, setDetail] = useState("");
  useEffect(() => {
    let channel: RealtimeChannel | null = null;
    let disposed = false;
    void (async () => {
      await client.realtime.setAuth();
      if (disposed) return;
      channel = client.channel(liveTopic(sessionId), { config: { private: true, presence: { key: (await client.auth.getUser()).data.user?.id ?? "" } } });
      channel
        .on("broadcast", { event: "view" }, ({ payload }) => applyView(payload as LiveView))
        .on("broadcast", { event: "board" }, ({ payload }) => applyBoardFromHost((payload as { board: Board }).board))
        .on("broadcast", { event: "drag" }, ({ payload }) => {
          const { document } = useEditor.getState();
          if (document) useEditor.setState({ document: applyMoves(document, payload as LiveDrag) });
        })
        .on("broadcast", { event: "pointer" }, ({ payload }) => useLive.getState().set({ pointer: (payload as { point: Point | null }).point }))
        .on("broadcast", { event: "ended" }, () => { setState("ended"); void channel?.unsubscribe(); })
        .on("broadcast", { event: "guests-off" }, () => { if (me.guest) { setState("removed"); void channel?.unsubscribe(); } })
        .on("presence", { event: "sync" }, () => {
          const present = Object.values(channel!.presenceState<LivePresence>()).some(metas => metas.some(meta => meta.role === "host"));
          useLive.getState().set({ hostHere: present, ...(present ? {} : { pointer: null }) });
        })
        .subscribe((status, error) => {
          if (status === "SUBSCRIBED") { setState(current => current === "connecting" ? "following" : current); void channel!.track(me); }
          if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
            console.error("tactics live channel", status, error);
            setDetail(error?.message ? `${status}: ${error.message}` : status);
            setState(current => current === "connecting" ? "failed" : current);
          }
        });
    })();
    return () => {
      disposed = true;
      if (channel) void client.removeChannel(channel);
      useLive.getState().set({ pointer: null, hostHere: false });
    };
  }, [client, sessionId, me]);
  return { state, detail };
}
