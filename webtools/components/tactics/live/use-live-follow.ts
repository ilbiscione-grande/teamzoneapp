"use client";

// Following a live lesson: the session's channel is listened to and the
// board follows the host. A view moves the board, frame and playhead (a
// playing board is played on here from where the host was); a board
// replaces the participant's copy; a drag moves objects on the way; the
// pointer shows where the host points. The chat's events go to the chat,
// and the participant's raised hand is part of their presence.
import type { RealtimeChannel, SupabaseClient } from "@supabase/supabase-js";
import { useCallback, useEffect, useRef, useState } from "react";
import type { ChatMessage } from "../../../lib/tactics/live-chat.ts";
import { applyBoard, applyMoves, liveTopic, type LiveDrag, type LivePresence, type LiveView } from "../../../lib/tactics/live.ts";
import type { Board, Point, ProjectDocument } from "../../../lib/tactics/model.ts";
import { useEditor } from "../store.ts";
import { listenChat, useChat } from "./chat-store.ts";
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

/** A change to the participant's copy of the document (never saved). */
function edit(change: (document: ProjectDocument) => ProjectDocument) {
  const { document } = useEditor.getState();
  if (document) useEditor.setState({ document: change(document) });
}

/** The follow state, Realtime's reason when the channel could not be opened, and the participant's hand. */
export function useLiveFollow(client: SupabaseClient, sessionId: string, me: LivePresence) {
  const [state, setState] = useState<FollowState>("connecting");
  const [detail, setDetail] = useState("");
  const [hand, setHandState] = useState<number | null>(null);
  const channelRef = useRef<RealtimeChannel | null>(null);
  const muted = useChat(store => store.muted);

  useEffect(() => {
    let disposed = false;
    void (async () => {
      await client.realtime.setAuth();
      const selfId = (await client.auth.getUser()).data.user?.id ?? "";
      if (disposed) return;
      useChat.getState().set({ selfId });
      const channel = client.channel(liveTopic(sessionId), { config: { private: true, presence: { key: selfId } } });
      channelRef.current = channel;
      channel
        .on("broadcast", { event: "view" }, ({ payload }) => applyView(payload as LiveView))
        .on("broadcast", { event: "board" }, ({ payload }) => edit(document => applyBoard(document, (payload as { board: Board }).board)))
        .on("broadcast", { event: "drag" }, ({ payload }) => edit(document => applyMoves(document, payload as LiveDrag)))
        .on("broadcast", { event: "pointer" }, ({ payload }) => useLive.getState().set({ pointer: (payload as { point: Point | null }).point }))
        .on("broadcast", { event: "ended" }, () => { setState("ended"); void channel.unsubscribe(); })
        .on("broadcast", { event: "guests-off" }, () => { if (me.guest) { setState("removed"); void channel.unsubscribe(); } })
        .on("presence", { event: "sync" }, () => {
          const present = Object.values(channel.presenceState<LivePresence>()).some(metas => metas.some(meta => meta.role === "host"));
          useLive.getState().set({ hostHere: present, ...(present ? {} : { pointer: null }) });
        });
      listenChat(channel, { id: selfId, onLowerHand: () => setHandState(null) });
      channel.subscribe(async (status, error) => {
        if (status === "SUBSCRIBED") {
          setState(current => current === "connecting" ? "following" : current);
          const { data } = await client.schema("api").rpc("list_tactics_live_messages", { target_session_id: sessionId });
          useChat.getState().add((data as ChatMessage[] | null) ?? []);
          if (!useChat.getState().open) useChat.getState().set({ unread: 0 });
        }
        if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
          console.error("tactics live channel", status, error);
          setDetail(error?.message ? `${status}: ${error.message}` : status);
          setState(current => current === "connecting" ? "failed" : current);
        }
      });
    })();
    return () => {
      disposed = true;
      if (channelRef.current) void client.removeChannel(channelRef.current);
      channelRef.current = null;
      useLive.getState().set({ pointer: null, hostHere: false });
    };
  }, [client, sessionId, me]);

  // What the host sees of this participant: name, hand and whether their chat is off.
  useEffect(() => {
    if (state === "following") void channelRef.current?.track({ ...me, hand, muted });
  }, [state, me, hand, muted]);

  const setHand = useCallback((raised: boolean) => setHandState(raised ? Date.now() : null), []);
  return { state, detail, hand, setHand };
}
