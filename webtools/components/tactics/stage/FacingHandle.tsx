"use client";

// Turning a selected player the way they face: a handle at the tip of the
// facing cone, dragged round the player and snapping to 15°. The player
// turns while dragging and the turn is kept on letting go.
import type Konva from "konva";
import { useState } from "react";
import { Circle, Group, Line } from "react-konva";
import type { PlayerObject } from "../../../lib/tactics/model.ts";
import { facingToRotation, snapAngle } from "../../../lib/tactics/facing.ts";
import { standingFacing } from "../../../lib/tactics/timeline.ts";
import { useEditor } from "../store.ts";
import { useStage } from "./stage-context.ts";

/** How far from the player's middle the handle sits, in metres. */
const REACH = 4.6;

export function FacingHandle({ item }: { item: PlayerObject }) {
  const shared = useStage();
  const [facing, setFacing] = useState<number | null>(null);
  const angle = facing ?? standingFacing(item);
  const radians = (angle * Math.PI) / 180;
  const tip = { x: item.x + Math.cos(radians) * REACH, y: item.y + Math.sin(radians) * REACH };
  const radius = shared.metresPerPixel() * 12;
  const turnTo = (point: { x: number; y: number }) => snapAngle((Math.atan2(point.y - item.y, point.x - item.x) * 180) / Math.PI);
  return (
    <Group>
      <Line points={[item.x, item.y, tip.x, tip.y]} stroke="#facc15" strokeWidth={0.12} dash={[0.4, 0.3]} listening={false} />
      <Circle x={tip.x} y={tip.y} radius={radius} fill="#facc15" stroke="#111827" strokeWidth={radius * 0.18} draggable
        onMouseDown={event => { event.cancelBubble = true; }} onTouchStart={event => { event.cancelBubble = true; }}
        onDragMove={event => {
          const next = turnTo({ x: event.target.x(), y: event.target.y() });
          setFacing(next);
          // The player turns at once; the store hears of it on letting go.
          (shared.nodes.get(item.id) as Konva.Group | undefined)?.rotation(facingToRotation(next, item.side));
        }}
        onDragEnd={event => {
          const next = turnTo({ x: event.target.x(), y: event.target.y() });
          setFacing(null);
          useEditor.getState().patch({ [item.id]: { rotation: facingToRotation(next, item.side) } });
        }} />
    </Group>
  );
}
