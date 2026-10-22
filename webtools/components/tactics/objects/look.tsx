"use client";

// How playing changes an object's look: faded, grown or lit. Shared by the
// object nodes, which otherwise draw only what the document says.
import { Circle } from "react-konva";
import type { Rendered } from "../../../lib/tactics/timeline.ts";

/** Opacity and scale for a node, from its own scale and the play's growth. */
export function look(item: Rendered, scale = 1) {
  const grow = item.grow ?? 1;
  return { opacity: item.opacity ?? 1, scaleX: scale * grow, scaleY: scale * grow };
}

/** A yellow halo while a highlight plays. */
export function Glow({ item, radius }: { item: Rendered; radius: number }) {
  if (!item.glow) return null;
  return <Circle radius={radius} fill="rgba(250,204,21,0.35)" stroke="#facc15" strokeWidth={0.25} opacity={item.glow} listening={false} perfectDrawEnabled={false} />;
}
