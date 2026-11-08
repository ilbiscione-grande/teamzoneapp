"use client";

// Dragging an object: Konva moves the node itself, so nothing in React
// renders while a finger moves. The other selected objects and the balls of
// moved players follow by moving their nodes directly. Only the drop is
// written to the document, where a dropped ball may stick to a player.
// Dropped on the bin beside the pitch, the dragged objects are removed: out of
// every frame with Shift held or "all frames" ticked, else out of this one.
import type Konva from "konva";
import { useRef } from "react";
import { dropBall } from "../../../lib/tactics/ball.ts";
import { keepOnGrass } from "../../../lib/tactics/document.ts";
import type { BallObject, TacticsObject } from "../../../lib/tactics/model.ts";
import { activeBoard, activeObjects, useEditor } from "../store.ts";
import { objectDrag, objectDrop, trashAt, useStage } from "./stage-context.ts";

type Start = Map<string, { x: number; y: number }>;

/** When a finger last went down on an object (use-object-drag): the mouse event after it is the same tap. */
let lastTouch = 0;

export function useObjectDrag(item: TacticsObject) {
  const shared = useStage();
  const starts = useRef<Start>(new Map());
  // Pressed while picked, picking several: taken out if it turns out a tap.
  const pickedOut = useRef(false);
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

  // Shift, or "all frames" ticked: the bin takes them out of every frame.
  const everyFrame = (event: Konva.KonvaEventObject<DragEvent>) => {
    const state = useEditor.getState();
    return (activeBoard(state)?.frames.length ?? 0) > 1 && ((event.evt as MouseEvent | undefined)?.shiftKey === true || state.allFrames);
  };

  const select = (additive: boolean) => {
    const { tool, selection, select, pickMany } = useEditor.getState();
    if (tool !== "select") return;
    // Picking several, a picked object goes out on a tap, not as it is pressed: pressed to be dragged, the picked ones move together.
    if (pickMany && selection.includes(item.id)) { pickedOut.current = true; return; }
    if (additive || pickMany) select([item.id], true);
    else if (!selection.includes(item.id)) select([item.id]);
  };
  /** A tap, no drag, on an object picked already: out of the selection. */
  const tapped = () => {
    if (!pickedOut.current) return;
    pickedOut.current = false;
    const { pickMany, select } = useEditor.getState();
    if (pickMany) select([item.id], true);
  };

  return {
    draggable: editable,
    onClick: () => { if (Date.now() - lastTouch >= 700) tapped(); },
    onTap: tapped,
    onMouseDown: (event: Konva.KonvaEventObject<MouseEvent>) => {
      if (useEditor.getState().tool === "select") event.cancelBubble = true;
      // The mouse event a touch is followed by would take a picked object out again.
      if (Date.now() - lastTouch < 700) return;
      select(event.evt.shiftKey);
    },
    onTouchStart: (event: Konva.KonvaEventObject<TouchEvent>) => {
      if (useEditor.getState().tool === "select") event.cancelBubble = true;
      lastTouch = Date.now();
      select(false);
    },
    onDragStart: (event: Konva.KonvaEventObject<DragEvent>) => {
      pickedOut.current = false;
      trashAt(shared, event.target.getStage(), true, everyFrame(event));
      starts.current = new Map();
      const objects = activeObjects(useEditor.getState());
      for (const mover of movers()) {
        // A line between players is where its players are: moved too, it would go twice as far.
        if (mover.type === "chain") continue;
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
      trashAt(shared, event.target.getStage(), true, everyFrame(event));
      if (objectDrag.size) {
        const moves = Object.fromEntries([...starts.current].map(([id, start]) => [id, { x: start.x + dx, y: start.y + dy }]));
        objectDrag.forEach(listen => listen(moves));
      }
    },
    onDragEnd: (event: Konva.KonvaEventObject<DragEvent>) => {
      const own = starts.current.get(item.id);
      const all = everyFrame(event);
      const binned = trashAt(shared, event.target.getStage(), true, all);
      trashAt(shared, null, false);
      if (!own) return;
      if (binned) {
        // The dragged objects go; a ball that only came along with a player stays where it was.
        const gone = new Set(movers().map(mover => mover.id));
        starts.current.forEach((start, id) => { if (!gone.has(id)) shared.nodes.get(id)?.position(start); });
        // The drag is over: what followed it (a line between players, an arrow) lets go of the
        // bin's place, so an undo brings the player back with them where they were.
        if (objectDrop.size) {
          const back = Object.fromEntries(starts.current);
          objectDrop.forEach(listen => listen(back));
        }
        useEditor.getState().removeObjects([...gone], all);
        starts.current = new Map();
        return;
      }
      const dx = event.target.x() - own.x;
      const dy = event.target.y() - own.y;
      const moved = new Map<string, { x: number; y: number }>();
      starts.current.forEach((start, id) => moved.set(id, keepOnGrass({ x: start.x + dx, y: start.y + dy })));
      const { attachBall, changeObjects } = useEditor.getState();
      changeObjects(objects => {
        // An arrow dragged away from its player comes loose; dragged along with them it stays.
        const placed = objects.map(other => !moved.has(other.id) ? other
          : other.type === "line" && other.from && !moved.has(other.from) ? { ...other, ...moved.get(other.id)!, from: null }
          : { ...other, ...moved.get(other.id)! });
        // A ball dragged on its own is dropped: it sticks to a player or lies loose.
        if (item.type !== "ball") return placed;
        return placed.map(other => other.id === item.id
          ? dropBall(other as BallObject, moved.get(item.id)!, placed, attachBall)
          : other);
      });
      starts.current = new Map();
      if (objectDrop.size) {
        const dropped = Object.fromEntries(moved);
        objectDrop.forEach(listen => listen(dropped));
      }
    },
  };
}
