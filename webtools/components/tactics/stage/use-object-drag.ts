"use client";

// Dragging an object: Konva moves the node itself, so nothing in React
// renders while a finger moves. The other selected objects and the balls of
// moved players follow by moving their nodes directly. Only the drop is
// written to the document, where a dropped ball may stick to a player.
// Dropped on the bin beside the pitch, the dragged objects are removed.
import type Konva from "konva";
import { useRef } from "react";
import { dropBall } from "../../../lib/tactics/ball.ts";
import { keepOnGrass } from "../../../lib/tactics/document.ts";
import type { BallObject, TacticsObject } from "../../../lib/tactics/model.ts";
import { activeObjects, useEditor } from "../store.ts";
import { trashAt, useStage } from "./stage-context.ts";

type Start = Map<string, { x: number; y: number }>;

export function useObjectDrag(item: TacticsObject) {
  const shared = useStage();
  const starts = useRef<Start>(new Map());
  // Only the select tool drags; the others draw or place over objects.
  const tool = useEditor(state => state.tool);
  const editable = shared.editable && !item.locked && tool === "select";

  // Who moves with this object: the selection when it is part of it.
  const movers = () => {
    const state = useEditor.getState();
    const objects = activeObjects(state);
    const ids = state.selection.includes(item.id) ? state.selection : [item.id];
    return objects.filter(other => ids.includes(other.id) && !other.locked);
  };

  const select = (additive: boolean) => {
    const { tool, selection, select } = useEditor.getState();
    if (tool !== "select") return;
    if (additive) select([item.id], true);
    else if (!selection.includes(item.id)) select([item.id]);
  };

  return {
    draggable: editable,
    onMouseDown: (event: Konva.KonvaEventObject<MouseEvent>) => {
      if (useEditor.getState().tool === "select") event.cancelBubble = true;
      select(event.evt.shiftKey);
    },
    onTouchStart: (event: Konva.KonvaEventObject<TouchEvent>) => {
      if (useEditor.getState().tool === "select") event.cancelBubble = true;
      select(false);
    },
    onDragStart: (event: Konva.KonvaEventObject<DragEvent>) => {
      trashAt(shared, event.target.getStage(), true);
      starts.current = new Map();
      const objects = activeObjects(useEditor.getState());
      for (const mover of movers()) {
        starts.current.set(mover.id, { x: mover.x, y: mover.y });
        // Balls held by a moving player come along.
        for (const ball of objects) {
          if (ball.type === "ball" && ball.attachedTo === mover.id && !starts.current.has(ball.id)) {
            starts.current.set(ball.id, { x: ball.x, y: ball.y });
          }
        }
      }
    },
    onDragMove: (event: Konva.KonvaEventObject<DragEvent>) => {
      const own = starts.current.get(item.id);
      if (!own) return;
      const dx = event.target.x() - own.x;
      const dy = event.target.y() - own.y;
      starts.current.forEach((start, id) => {
        if (id === item.id) return;
        shared.nodes.get(id)?.position({ x: start.x + dx, y: start.y + dy });
      });
      trashAt(shared, event.target.getStage(), true);
    },
    onDragEnd: (event: Konva.KonvaEventObject<DragEvent>) => {
      const own = starts.current.get(item.id);
      const binned = trashAt(shared, event.target.getStage(), true);
      trashAt(shared, null, false);
      if (!own) return;
      if (binned) {
        // The dragged objects go; a ball that only came along with a player stays where it was.
        const gone = new Set(movers().map(mover => mover.id));
        starts.current.forEach((start, id) => { if (!gone.has(id)) shared.nodes.get(id)?.position(start); });
        useEditor.getState().changeObjects(objects => objects.filter(other => !gone.has(other.id)));
        useEditor.getState().select([]);
        starts.current = new Map();
        return;
      }
      const dx = event.target.x() - own.x;
      const dy = event.target.y() - own.y;
      const moved = new Map<string, { x: number; y: number }>();
      starts.current.forEach((start, id) => moved.set(id, keepOnGrass({ x: start.x + dx, y: start.y + dy })));
      const { attachBall, changeObjects } = useEditor.getState();
      changeObjects(objects => {
        const placed = objects.map(other => moved.has(other.id) ? { ...other, ...moved.get(other.id)! } : other);
        // A ball dragged on its own is dropped: it sticks to a player or lies loose.
        if (item.type !== "ball") return placed;
        return placed.map(other => other.id === item.id
          ? dropBall(other as BallObject, moved.get(item.id)!, placed, attachBall)
          : other);
      });
      starts.current = new Map();
    },
  };
}
