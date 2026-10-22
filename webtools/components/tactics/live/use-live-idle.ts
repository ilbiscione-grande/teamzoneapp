"use client";

// A lesson left running ends by itself. The host's page tells the database
// when the host does something (at most once a minute), warns the host
// five minutes before 30 quiet minutes are up, and then ends the lesson for
// everyone. A chat message, a drawing or a move by the one with the floor
// counts as activity too.
import type { SupabaseClient } from "@supabase/supabase-js";
import { useEffect } from "react";
import { idleState } from "../../../lib/tactics/live.ts";
import { useChat } from "./chat-store.ts";
import { useDraw } from "./draw-store.ts";
import { useLive } from "./live-store.ts";
import { broadcastOnce } from "./use-live-host.ts";

const CHECK_MS = 30_000;
const TOUCH_MS = 60_000;

/** Ends the host's lesson: everyone is told, then the database. */
export async function endLesson(client: SupabaseClient, sessionId: string, notice = "") {
  await broadcastOnce(client, sessionId, "ended");
  await client.schema("api").rpc("end_tactics_live", { target_session_id: sessionId });
  useLive.getState().set({ session: null, participants: [], idle: "active", notice });
  useDraw.getState().set({ strokes: [], floorHolder: null, floorName: null });
}

export function useLiveIdle(client: SupabaseClient | null, sessionId: string | undefined) {
  useEffect(() => {
    if (!client || !sessionId) return;
    let touched = Date.now();
    useLive.getState().markActivity();
    const unsubscribe = useChat.subscribe((state, before) => {
      if (state.messages.length > before.messages.length) useLive.getState().markActivity();
    });
    const unsubscribeDraw = useDraw.subscribe((state, before) => {
      if (state.strokes.length > before.strokes.length) useLive.getState().markActivity();
    });
    const check = async () => {
      const { activityAt } = useLive.getState();
      const now = Date.now();
      if (activityAt > touched && now - touched >= TOUCH_MS) {
        touched = now;
        const { data: open } = await client.schema("api").rpc("touch_tactics_live", { target_session_id: sessionId });
        if (open === false) {
          useLive.getState().set({ session: null, participants: [], idle: "active", notice: "Livelektionen har avslutats." });
          return;
        }
      }
      const state = idleState(activityAt, now);
      if (state === "expired") await endLesson(client, sessionId, "Livelektionen avslutades efter 30 minuter utan aktivitet.");
      else useLive.getState().set({ idle: state });
    };
    const timer = setInterval(() => void check(), CHECK_MS);
    return () => { clearInterval(timer); unsubscribe(); unsubscribeDraw(); };
  }, [client, sessionId]);
}
