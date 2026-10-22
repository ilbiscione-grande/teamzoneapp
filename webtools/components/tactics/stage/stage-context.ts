"use client";

// What the objects on the stage share: the Konva node of every object (so a
// drag can move others along without React), the pitch group (for pointer
// positions in metres) and how large a screen pixel is in metres.
import type Konva from "konva";
import { createContext, useContext } from "react";

export type StageShared = {
  nodes: Map<string, Konva.Node>;
  content: React.RefObject<Konva.Group | null>;
  /** Metres per screen pixel at the current zoom: for handles of a finger's size. */
  metresPerPixel: () => number;
  editable: boolean;
  /** The bin beside the pitch: shown while an object is dragged, removing what is dropped on it. */
  trash?: React.RefObject<HTMLDivElement | null>;
};

/** Shows the bin while dragging, lit when the pointer is over it; whether it is. */
export function trashAt(shared: StageShared, stage: Konva.Stage | null, dragging: boolean): boolean {
  const bin = shared.trash?.current;
  if (!bin) return false;
  const pointer = stage?.getPointerPosition();
  let over = false;
  if (dragging && stage && pointer) {
    const box = stage.container().getBoundingClientRect();
    const zone = bin.getBoundingClientRect();
    const x = box.left + pointer.x, y = box.top + pointer.y;
    over = x >= zone.left && x <= zone.right && y >= zone.top && y <= zone.bottom;
  }
  bin.dataset.active = String(dragging);
  bin.dataset.over = String(over);
  return over;
}

export const StageContext = createContext<StageShared | null>(null);

/** The mounted Konva stage, for recording the board as a video. */
export const stageHolder: { current: Konva.Stage | null } = { current: null };

export function useStage(): StageShared {
  const shared = useContext(StageContext);
  if (!shared) throw new Error("useStage outside the board stage");
  return shared;
}

/** Registers an object's node by id while it is mounted. */
export function nodeRef(shared: StageShared, id: string) {
  return (node: Konva.Node | null) => {
    if (node) shared.nodes.set(id, node);
    else shared.nodes.delete(id);
  };
}
