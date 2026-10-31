"use client";

// Drawing with a finger or the mouse: a pass, a run or a line from where the
// finger goes down to where it lifts; a freehand stroke along the way; an
// area from corner to corner. Placing tools put an object where you tap.
// The ruler measures from where the finger goes down to where it lifts; the
// measure stays shown, not saved, and the ruler stays in hand.
import { useState } from "react";
import { createObject, createPlayer, keepOnGrass, newId } from "../../../lib/tactics/document.ts";
import type { Point, TacticsObject } from "../../../lib/tactics/model.ts";
import { activeObjects, useEditor, type Tool } from "../store.ts";

export type Draft = { tool: Tool; start: Point; current: Point; path: number[] };

const DRAW_TOOLS = new Set<Tool>(["arrow", "run", "dribble", "line", "freehand", "rect", "ellipse", "ruler"]);
export const isDrawTool = (tool: Tool) => DRAW_TOOLS.has(tool);
export const isPlaceTool = (tool: Tool) => tool !== "select" && !DRAW_TOOLS.has(tool);

const base = (point: Point) => ({ id: newId(), x: point.x, y: point.y, rotation: 0, locked: false, hidden: false });

/** The object a finished draft becomes, or null when it is too small to mean anything. */
export function draftObject(draft: Draft): TacticsObject | null {
  const { start, current } = draft;
  const length = Math.hypot(current.x - start.x, current.y - start.y);
  if (draft.tool === "freehand") {
    if (draft.path.length < 6) return null;
    return { ...base(start), type: "freehand", points: draft.path, arrow: "end", dashed: false, color: "#ffffff", width: 0.3 };
  }
  if (length < 0.8) return null;
  if (draft.tool === "rect" || draft.tool === "ellipse") {
    const center = { x: (start.x + current.x) / 2, y: (start.y + current.y) / 2 };
    return {
      ...base(center), type: draft.tool, width: Math.abs(current.x - start.x), height: Math.abs(current.y - start.y),
      color: "#facc15", fill: 0.35, dashed: draft.tool === "ellipse",
    };
  }
  return {
    ...base(start), type: "line", points: [0, 0, current.x - start.x, current.y - start.y], control: null,
    arrow: draft.tool === "line" ? "none" : "end", dashed: draft.tool === "run", wavy: draft.tool === "dribble", color: "#ffffff", width: 0.3,
  };
}

export function useDrawing(pointer: () => Point | null) {
  const [draft, setDraft] = useState<Draft | null>(null);

  const start = () => {
    const { tool } = useEditor.getState();
    const point = pointer();
    if (!point || !isDrawTool(tool)) return false;
    if (tool === "ruler") useEditor.getState().setRuler(null);
    setDraft({ tool, start: point, current: point, path: [0, 0] });
    return true;
  };
  const move = () => {
    const point = pointer();
    if (!draft || !point) return;
    if (draft.tool !== "freehand") {
      setDraft({ ...draft, current: point });
      return;
    }
    const x = point.x - draft.start.x, y = point.y - draft.start.y;
    const lastX = draft.path[draft.path.length - 2], lastY = draft.path[draft.path.length - 1];
    // A new point only every 40 cm keeps the stroke smooth and small.
    if (Math.hypot(x - lastX, y - lastY) < 0.4) return;
    setDraft({ ...draft, current: point, path: [...draft.path, x, y] });
  };
  const end = () => {
    if (!draft) return;
    if (draft.tool === "ruler") {
      setDraft(null);
      if (Math.hypot(draft.current.x - draft.start.x, draft.current.y - draft.start.y) >= 0.3) useEditor.getState().setRuler({ from: draft.start, to: draft.current });
      return;
    }
    const made = draftObject(draft);
    setDraft(null);
    if (!made) return;
    const { changeObjects, select, setTool } = useEditor.getState();
    changeObjects(objects => [...objects, made]);
    // One stroke at a time: back to selecting, with the new object chosen.
    setTool("select");
    select([made.id]);
  };

  /** Places the tool's object where the pointer is. */
  const place = () => {
    const { tool, changeObjects, select } = useEditor.getState();
    const point = pointer();
    if (!point || !isPlaceTool(tool)) return;
    const at = keepOnGrass(point);
    const objects = activeObjects(useEditor.getState());
    let made: TacticsObject;
    if (tool === "player-home" || tool === "player-away") {
      const side = tool === "player-home" ? "home" : "away";
      made = createPlayer(at, side, objects);
    } else {
      made = createObject(tool as Parameters<typeof createObject>[0], at);
    }
    changeObjects(current => [...current, made]);
    if (made.type === "text") select([made.id]);
  };

  return { draft, start, move, end, place };
}
