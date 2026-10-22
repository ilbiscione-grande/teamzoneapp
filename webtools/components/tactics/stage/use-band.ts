"use client";

// The selecting band: dragged over the grass with the whole view in sight,
// it selects every object it touches (Shift adds to the selection). Drawn
// in the stage's pixels directly while it moves.
import Konva from "konva";
import { useRef } from "react";
import type { Point } from "../../../lib/tactics/model.ts";
import { useEditor } from "../store.ts";

type PointerEvent = Konva.KonvaEventObject<globalThis.PointerEvent>;
const at = (event: PointerEvent) => event.target.getStage()?.getPointerPosition() ?? null;

export function useBand(nodes: Map<string, Konva.Node>) {
  const band = useRef<Konva.Rect>(null);
  const start = useRef<Point | null>(null);
  const moved = useRef(false);

  const cancel = () => {
    start.current = null;
    band.current?.visible(false);
    band.current?.getLayer()?.batchDraw();
  };

  return {
    band,
    cancel,
    begin: (event: PointerEvent) => {
      start.current = at(event);
      moved.current = false;
    },
    move: (event: PointerEvent) => {
      const from = start.current, to = from && at(event);
      if (!from || !to) return;
      if (!moved.current && Math.hypot(to.x - from.x, to.y - from.y) < 6) return;
      moved.current = true;
      band.current?.setAttrs({ x: Math.min(from.x, to.x), y: Math.min(from.y, to.y), width: Math.abs(to.x - from.x), height: Math.abs(to.y - from.y), visible: true });
      band.current?.getLayer()?.batchDraw();
    },
    /** Selects what the band touches among the ids shown. */
    end: (event: PointerEvent, shown: string[]) => {
      const from = start.current, to = at(event);
      cancel();
      if (!from || !to || !moved.current) return;
      const area = { x: Math.min(from.x, to.x), y: Math.min(from.y, to.y), width: Math.abs(to.x - from.x), height: Math.abs(to.y - from.y) };
      const touched = shown.filter(id => {
        const node = nodes.get(id);
        return node && Konva.Util.haveIntersection(area, node.getClientRect());
      });
      const { select, selection } = useEditor.getState();
      select(event.evt.shiftKey ? [...new Set([...selection, ...touched])] : touched);
    },
    /** A band that moved ends in a click on the grass; that click must not clear what it chose. */
    consumeClick: () => {
      const was = moved.current;
      moved.current = false;
      return was;
    },
  };
}
