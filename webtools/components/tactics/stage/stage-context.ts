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
};

export const StageContext = createContext<StageShared | null>(null);

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
