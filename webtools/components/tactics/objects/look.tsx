"use client";

// How playing changes an object's look: faded, grown or lit. Shared by the
// object nodes, which otherwise draw only what the document says.
import { Circle, Group } from "react-konva";
import type { Rendered } from "../../../lib/tactics/timeline.ts";

/** Opacity and scale for a node, from its own scale and the play's growth. */
export function look(item: Rendered, scale = 1) {
  const grow = item.grow ?? 1;
  return { opacity: item.opacity ?? 1, scaleX: scale * grow, scaleY: scale * grow };
}

/** A yellow glow while a highlight plays: soft light fading outwards, a bright ring round it. */
export function Glow({ item, radius }: { item: Rendered; radius: number }) {
  if (!item.glow) return null;
  return (
    <Group opacity={item.glow} listening={false}>
      <Circle radius={radius * 1.35} listening={false} perfectDrawEnabled={false}
        fillRadialGradientStartPoint={{ x: 0, y: 0 }} fillRadialGradientStartRadius={0}
        fillRadialGradientEndPoint={{ x: 0, y: 0 }} fillRadialGradientEndRadius={radius * 1.35}
        fillRadialGradientColorStops={[0, "rgba(250,204,21,0.55)", 0.6, "rgba(250,204,21,0.3)", 1, "rgba(250,204,21,0)"]} />
      <Circle radius={radius * 0.8} stroke="rgba(11,17,28,0.45)" strokeWidth={0.45} listening={false} perfectDrawEnabled={false} />
      <Circle radius={radius * 0.8} stroke="#facc15" strokeWidth={0.28} listening={false} perfectDrawEnabled={false} />
    </Group>
  );
}
