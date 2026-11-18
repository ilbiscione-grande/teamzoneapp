"use client";

// Drawing a zone of one's own (lib/tactics/zone.ts): each tap on the pitch
// puts a corner, a line follows the pointer to the next, and tapping the
// first corner, tapping the last one again or pressing Enter closes it into a
// zone. Backspace takes the last corner back; changing tool, board or frame
// drops them. The tool stays in hand for the next zone.
import { useEffect, useState } from "react";
import type { Point } from "../../../lib/tactics/model.ts";
import { tapCorner, zoneFrom } from "../../../lib/tactics/zone.ts";
import { useEditor } from "../store.ts";

/** How near a tap must be to a corner to count as on it, in screen pixels. */
const REACH_PX = 14;

/** pixel: metres per screen pixel just now. */
export function useZoneDraw(pointer: () => Point | null, pixel: () => number) {
  const tool = useEditor(state => state.tool);
  const boardId = useEditor(state => state.boardId);
  const frameIndex = useEditor(state => state.frameIndex);
  const [corners, setCorners] = useState<Point[]>([]);
  const [hover, setHover] = useState<Point | null>(null);

  useEffect(() => { setCorners([]); setHover(null); }, [tool, boardId, frameIndex]);

  const close = (list: Point[]) => {
    setCorners([]);
    setHover(null);
    const made = zoneFrom(list);
    if (made) useEditor.getState().changeObjects(objects => [...objects, made]);
  };

  useEffect(() => {
    if (corners.length === 0) return;
    const onKey = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement | null;
      if (target?.closest("input, textarea, select, [contenteditable]")) return;
      if (event.key === "Enter") { event.preventDefault(); close(corners); }
      else if (event.key === "Backspace") { event.preventDefault(); event.stopImmediatePropagation(); setCorners(corners.slice(0, -1)); }
    };
    // Before the editor's own keys, so Backspace takes a corner back rather than removing anything.
    window.addEventListener("keydown", onKey, true);
    return () => window.removeEventListener("keydown", onKey, true);
  }); // eslint-disable-line react-hooks/exhaustive-deps

  const tap = () => {
    const at = pointer();
    if (!at) return;
    const next = tapCorner(corners, at, pixel() * REACH_PX);
    if (next.close) close(next.corners);
    else setCorners(next.corners);
  };
  const move = () => { if (corners.length > 0) setHover(pointer()); };

  return { corners, hover, tap, move, close: () => close(corners) };
}
