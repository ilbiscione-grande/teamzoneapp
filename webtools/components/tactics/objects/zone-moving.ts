"use client";

// A zone's corner or side middle being dragged by its handle (ZoneHandles),
// before the drop is written: the zone (ZoneNode) is drawn with it applied.
import { create } from "zustand";
import type { Point } from "../../../lib/tactics/model.ts";

export type Moving = { id: string; kind: "corner" | "side"; index: number; at: Point };

export const useZoneMoving = create<{ moving: Moving | null; set: (moving: Moving | null) => void }>(set => ({
  moving: null,
  set: moving => set({ moving }),
}));
