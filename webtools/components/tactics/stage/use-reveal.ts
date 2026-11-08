"use client";

// A phone's panel opens over the foot of the board. What is chosen is then
// panned into the part still showing above it, the zoom kept, unless it
// already shows there; when the panel closes the view goes back as it was.
import { useEffect, useRef } from "react";
import { pitchToFrame, type Fit, type Viewport } from "../../../lib/tactics/geometry.ts";
import type { Point, TacticsObject } from "../../../lib/tactics/model.ts";
import { activeObjects, useEditor } from "../store.ts";

/** Room kept round the chosen object at the edges of what shows. */
const MARGIN = 32;

/** Where an object is, for bringing it into view: a line's middle, a line between players their middle, or its place. */
function middleOf(item: TacticsObject, objects: TacticsObject[]): Point {
  if (item.type === "chain") {
    const players = objects.filter(other => item.players.includes(other.id));
    if (players.length) return { x: players.reduce((sum, p) => sum + p.x, 0) / players.length, y: players.reduce((sum, p) => sum + p.y, 0) / players.length };
  }
  if (item.type === "line") return { x: item.x + (item.points[0] + item.points[2]) / 2, y: item.y + (item.points[1] + item.points[3]) / 2 };
  return { x: item.x, y: item.y };
}

/** height: the board's; a new size resets the view, so the selection is brought in again. */
export function useReveal(view: { live: React.RefObject<Viewport>; apply: (next: Viewport, commit: boolean) => void }, fit: Fit, width: number, height: number, tilt: boolean) {
  const reveal = useEditor(state => state.reveal);
  const before = useRef<Viewport | null>(null);
  useEffect(() => {
    if (reveal === null) {
      if (before.current) view.apply(before.current, true);
      before.current = null;
      return;
    }
    const state = useEditor.getState();
    const objects = activeObjects(state);
    const chosen = objects.filter(item => state.selection.includes(item.id));
    if (!chosen.length || width === 0 || tilt) return;
    const middles = chosen.map(item => middleOf(item, objects));
    const at = pitchToFrame({ x: middles.reduce((sum, p) => sum + p.x, 0) / middles.length, y: middles.reduce((sum, p) => sum + p.y, 0) / middles.length }, fit);
    const now = view.live.current;
    const screen = { x: now.x + at.x * now.scale, y: now.y + at.y * now.scale };
    const outside = screen.y < MARGIN || screen.y > reveal - MARGIN;
    const aside = screen.x < MARGIN || screen.x > width - MARGIN;
    if (!outside && !aside) return;
    before.current ??= now;
    view.apply({
      scale: now.scale,
      x: aside ? width / 2 - at.x * now.scale : now.x,
      y: outside ? reveal / 2 - at.y * now.scale : now.y,
    }, true);
    // When the panel opens or closes, or the board's size resets the view; not as the view moves after.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [reveal, width, height]);
}
