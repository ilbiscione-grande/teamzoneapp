"use client";

// Drawing and the floor in a live lesson, in this browser: the shared
// strokes, a participant's own notes (only here), the drawing mode, who has
// the floor, and whether this participant has the pen out. The channel's
// events feed it; moves by the one with the floor go to a handler.
import type { RealtimeChannel } from "@supabase/supabase-js";
import { create } from "zustand";
import { mergeStrokes, type DrawMode, type Stroke } from "../../../lib/tactics/live-draw.ts";
import type { LiveDrag } from "../../../lib/tactics/live.ts";

type DrawState = {
  strokes: Stroke[];
  /** A participant's own notes, per board, never sent. */
  own: Stroke[];
  drawMode: DrawMode;
  floorHolder: string | null;
  floorName: string | null;
  /** Participating: drawing instead of zooming and panning. */
  pen: boolean;
  /** Participating: why a stroke could not be sent. */
  error: string;
  addStrokes: (incoming: Stroke[]) => void;
  set: (changes: Partial<Omit<DrawState, "addStrokes" | "set">>) => void;
};

export const useDraw = create<DrawState>((set, get) => ({
  strokes: [],
  own: [],
  drawMode: "off",
  floorHolder: null,
  floorName: null,
  pen: false,
  error: "",
  addStrokes: incoming => set({ strokes: mergeStrokes(get().strokes, incoming) }),
  set: changes => set(changes),
}));

export type FloorMove = LiveDrag & { dropped: boolean; by: string };

/** Drawing's and the floor's events on a lesson's channel. */
export function listenDraw(channel: RealtimeChannel, onFloorMove: (move: FloorMove) => void) {
  channel
    .on("broadcast", { event: "stroke" }, ({ payload }) => useDraw.getState().addStrokes([payload as Stroke]))
    .on("broadcast", { event: "strokes-cleared" }, ({ payload }) => {
      const { boardId } = payload as { boardId: string | null };
      useDraw.getState().set({ strokes: boardId ? useDraw.getState().strokes.filter(stroke => stroke.board_id !== boardId) : [] });
    })
    .on("broadcast", { event: "settings" }, ({ payload }) => {
      const { drawMode } = payload as { drawMode?: DrawMode };
      if (drawMode) useDraw.getState().set({ drawMode, ...(drawMode === "off" ? { pen: false } : {}) });
    })
    .on("broadcast", { event: "floor" }, ({ payload }) => {
      const { profileId, name } = payload as { profileId: string | null; name: string | null };
      useDraw.getState().set({ floorHolder: profileId, floorName: name });
    })
    .on("broadcast", { event: "floor-move" }, ({ payload }) => onFloorMove(payload as FloorMove));
}
