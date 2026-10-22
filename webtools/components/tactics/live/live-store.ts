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
  /** Hosting: why the channel could not be opened, when it could not. */
  channelError: string;
  /** Hosting: sends on the lesson's channel while it is open. */
  send: ((event: string, payload: object) => void) | null;
  /** Hosting: when the host last did something, and whether the lesson is about to end for want of it. */
  activityAt: number;
  idle: "active" | "warning";
  /** Hosting: a word about the lesson, such as that it ended by itself. */
  notice: string;
  markActivity: () => void;
  set: (changes: Partial<Omit<LiveState, "set">>) => void;
};

export const useLive = create<LiveState>(set => ({
  session: null,
  participants: [],
  pointer: null,
  hostHere: false,
  channelError: "",
  send: null,
  activityAt: 0,
  idle: "active",
  notice: "",
  markActivity: () => set({ activityAt: Date.now(), idle: "active" }),
  set: changes => set(changes),
}));

/** The channel's presence as a list: everyone but the host, by name. */
export function participantsOf(state: Record<string, LivePresence[]>): Participant[] {
  return Object.entries(state)
    .flatMap(([key, metas]) => metas[0] ? [{ ...metas[0], key }] : [])
    .filter(entry => entry.role === "participant")
    .sort((a, b) => a.name.localeCompare(b.name, "sv"));
}
