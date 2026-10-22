"use client";

// A live lesson in this browser: as host, the session and who is in it; as
// participant, the host's pointer and whether the host is there.
import { create } from "zustand";
import type { LivePresence, LiveSession } from "../../../lib/tactics/live.ts";
import type { Point } from "../../../lib/tactics/model.ts";

export type Participant = LivePresence & { key: string };

type LiveState = {
  /** Hosting: the running session, or null. */
  session: LiveSession | null;
  participants: Participant[];
  /** Participating: the host's pointer on the pitch, and whether the host is connected. */
  pointer: Point | null;
  hostHere: boolean;
  set: (changes: Partial<Omit<LiveState, "set">>) => void;
};

export const useLive = create<LiveState>(set => ({
  session: null,
  participants: [],
  pointer: null,
  hostHere: false,
  set: changes => set(changes),
}));

/** The channel's presence as a list: everyone but the host, by name. */
export function participantsOf(state: Record<string, LivePresence[]>): Participant[] {
  return Object.entries(state)
    .flatMap(([key, metas]) => metas[0] ? [{ ...metas[0], key }] : [])
    .filter(entry => entry.role === "participant")
    .sort((a, b) => a.name.localeCompare(b.name, "sv"));
}
