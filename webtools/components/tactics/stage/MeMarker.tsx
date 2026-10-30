"use client";

// The one watching a shared link (lib/tactics/me.ts): a bright ring on the
// ground round their player, and "DU" above it on the flat board. Tilted,
// the ring lies on the tilted ground and Figures3D writes "DU" over the
// figure instead.
import { Circle, Group, Text } from "react-konva";
import { PLAYER_RADIUS } from "../../../lib/tactics/ball.ts";
import type { Point } from "../../../lib/tactics/model.ts";

export const ME_COLOUR = "#facc15";

export function MeMarker({ at, upright, label = true }: { at: Point; upright: number; label?: boolean }) {
  const radius = PLAYER_RADIUS * 1.7;
  return (
    <Group x={at.x} y={at.y} listening={false}>
      <Circle radius={radius} fill={ME_COLOUR} opacity={0.28} listening={false} perfectDrawEnabled={false} />
      <Circle radius={radius} stroke={ME_COLOUR} strokeWidth={0.35} listening={false} perfectDrawEnabled={false} />
      {label && (
        <Group rotation={upright}>
          <Text text="DU" x={-4} y={-radius - 2.4} width={8} align="center" fontSize={1.9} fontStyle="bold" fill={ME_COLOUR}
            stroke="rgba(11,17,28,0.85)" strokeWidth={0.25} fillAfterStrokeEnabled listening={false} />
        </Group>
      )}
    </Group>
  );
}
