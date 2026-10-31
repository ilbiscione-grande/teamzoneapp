"use client";

// Where the selection is on the screen, in the board's pixels, for the
// quick menu over it: read from the objects' nodes once they are drawn, and
// gone while the selection is dragged.
import type Konva from "konva";
import { useEffect, useState } from "react";
import { objectDrag, objectDrop } from "./stage-context.ts";

export type ScreenBox = { left: number; top: number; right: number; bottom: number };

/** watch: what moves the selection on the screen (its objects, the zoom, the board's size). */
export function useSelectionBox(nodes: Map<string, Konva.Node>, selection: string[], enabled: boolean, watch: unknown[]): ScreenBox | null {
  const [box, setBox] = useState<ScreenBox | null>(null);
  const [moving, setMoving] = useState(false);
  useEffect(() => {
    const drag = () => setMoving(true);
    const drop = () => setMoving(false);
    objectDrag.add(drag);
    objectDrop.add(drop);
    return () => { objectDrag.delete(drag); objectDrop.delete(drop); };
  }, []);
  // A drag that ends in the bin drops nothing; the selection goes with it.
  useEffect(() => setMoving(false), [selection]);
  useEffect(() => {
    if (!enabled || selection.length === 0) { setBox(null); return; }
    // Once the board's own renderer has put the change on its nodes.
    const frame = setTimeout(() => {
      let next: ScreenBox | null = null;
      for (const id of selection) {
        const node = nodes.get(id);
        if (!node || !node.isVisible()) continue;
        const rect = node.getClientRect();
        next = next
          ? { left: Math.min(next.left, rect.x), top: Math.min(next.top, rect.y), right: Math.max(next.right, rect.x + rect.width), bottom: Math.max(next.bottom, rect.y + rect.height) }
          : { left: rect.x, top: rect.y, right: rect.x + rect.width, bottom: rect.y + rect.height };
      }
      setBox(next);
    }, 0);
    return () => clearTimeout(frame);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [enabled, selection, nodes, ...watch]);
  return moving ? null : box;
}
