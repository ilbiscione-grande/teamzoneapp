"use client";

// Hosting a live lesson: the session's channel is opened while it runs, and
// what the board does is sent on it. Where the board is goes at once (a
// scrub a little slower), the board in hand when it changes, objects while
// they are dragged, the pointer while it moves over the pitch. Someone joining gets the whole state.
import type { RealtimeChannel, SupabaseClient } from "@supabase/supabase-js";
import { useEffect } from "react";
import { liveTopic, throttle, viewChanged, type LiveView } from "../../../lib/tactics/live.ts";
import { objectDrag, pitchPointer } from "../stage/stage-context.ts";
import { activeBoard, useEditor } from "../store.ts";
import { listenChat, useChat } from "./chat-store.ts";
import { participantsOf, useLive } from "./live-store.ts";
import { useLiveHostChat } from "./use-live-host-chat.ts";
import { useLiveIdle } from "./use-live-idle.ts";

type State = ReturnType<typeof useEditor.getState>;
const viewOf = (state: State): LiveView | null => state.boardId === null ? null : {
  boardId: state.boardId, frameIndex: state.frameIndex, playhead: state.playhead, playing: state.playing, speed: state.speed, loop: state.loop,
};

export function useLiveHost(client: SupabaseClient | null) {
  const projectId = useEditor(state => state.meta?.id);
  const sessionId = useLive(state => state.session?.id);
  useLiveHostChat(client, sessionId);
  useLiveIdle(client, sessionId);

  // A session still running after a reload is picked up again.
  useEffect(() => {
    if (!client || !projectId) return;
    void client.schema("api").rpc("get_tactics_live", { target_project_id: projectId }).then(({ data }) => {
      if (data) useLive.getState().set({ session: data });
    });
  }, [client, projectId]);

  useEffect(() => {
    if (!client || !sessionId) return;
    let channel: RealtimeChannel | null = null;
    let ready = false;
    let lastView: LiveView | null = null;
    let lastBoard: unknown = null;
    const sendQuietly = (event: string, payload: object) => { if (ready) void channel?.send({ type: "broadcast", event, payload }); };
    // Whatever the host sends is the host doing something, save the heartbeat below.
    const send = (event: string, payload: object) => { useLive.getState().markActivity(); sendQuietly(event, payload); };
    const sendView = throttle((view: LiveView) => send("view", view), 60);
    const sendBoard = throttle(() => {
      const board = activeBoard(useEditor.getState());
      if (board) send("board", { board });
    }, 250);
    const sendPointer = throttle((point: { x: number; y: number } | null) => send("pointer", { point }), 50);
    const sendDrag = throttle((moves: Record<string, { x: number; y: number }>) => {
      const { boardId, frameIndex } = useEditor.getState();
      if (boardId) send("drag", { boardId, frameIndex, moves });
    }, 40);
    // Everything, for someone who just came in.
    const sync = () => {
      const { chatMode, hands } = useChat.getState();
      send("settings", { chatMode, hands });
      const state = useEditor.getState();
      const board = activeBoard(state);
      if (board) send("board", { board });
      const view = viewOf(state);
      if (view) send("view", view);
    };

    const unsubscribe = useEditor.subscribe((state, before) => {
      const view = viewOf(state);
      if (view && viewChanged(lastView, view)) {
        lastView = view;
        if (state.boardId !== before.boardId) sync(); else sendView.call(view);
      }
      const board = activeBoard(state);
      if (board && board !== lastBoard && state.boardId === before.boardId) { lastBoard = board; sendBoard.call(); }
    });
    // While playing, the participants are kept in step now and then.
    const heartbeat = setInterval(() => { const view = viewOf(useEditor.getState()); if (view?.playing) sendQuietly("view", view); }, 2000);
    pitchPointer.add(sendPointer.call);
    objectDrag.add(sendDrag.call);

    void (async () => {
      await client.realtime.setAuth();
      channel = client.channel(liveTopic(sessionId), { config: { private: true, presence: { key: "host" } } });
      channel
        .on("presence", { event: "sync" }, () => useLive.getState().set({ participants: participantsOf(channel!.presenceState()) }))
        .on("presence", { event: "join" }, ({ key }) => { if (key !== "host") { useLive.getState().markActivity(); sync(); } });
      listenChat(channel);
      channel.subscribe((status, error) => {
          if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
            console.error("tactics live channel", status, error);
            useLive.getState().set({ channelError: error?.message ? `${status}: ${error.message}` : status });
          }
          if (status !== "SUBSCRIBED") return;
          useLive.getState().set({ channelError: "" });
          ready = true;
          useLive.getState().set({ send });
          void channel!.track({ role: "host", name: "Läraren", guest: false });
          lastView = viewOf(useEditor.getState());
          sync();
        });
    })();

    return () => {
      ready = false;
      clearInterval(heartbeat);
      unsubscribe();
      pitchPointer.delete(sendPointer.call);
      objectDrag.delete(sendDrag.call);
      sendView.cancel(); sendBoard.cancel(); sendPointer.cancel(); sendDrag.cancel();
      if (channel) void client.removeChannel(channel);
      useLive.getState().set({ participants: [], send: null });
    };
  }, [client, sessionId]);
}

/** Tells everyone on the channel, before the session's state changes in the database. */
export async function broadcastOnce(client: SupabaseClient, sessionId: string, event: string, payload: object = {}) {
  const channel = client.getChannels().find(item => item.topic === `realtime:${liveTopic(sessionId)}`);
  await channel?.send({ type: "broadcast", event, payload });
}
