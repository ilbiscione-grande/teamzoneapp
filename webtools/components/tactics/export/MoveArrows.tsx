"use client";

// A still picture's moves (lib/tactics/marks.ts movesInto): dashed arrows
// under the objects, white for the players, yellow for the ball's passes.
import { Arrow, Group } from "react-konva";
import type { Trail } from "../../../lib/tactics/marks.ts";

export function MoveArrows({ moves }: { moves: Trail[] }) {
  if (moves.length === 0) return null;
  return (
    <Group listening={false}>
      {moves.map((move, index) => {
        const color = move.ball ? "#fde047" : "#ffffff";
        return (
          <Arrow key={index} points={move.points} stroke={color} fill={color} strokeWidth={0.26} dash={[0.8, 0.55]}
            pointerLength={1.3} pointerWidth={1.2} lineCap="round" lineJoin="round" opacity={0.9} listening={false} perfectDrawEnabled={false} />
        );
      })}
    </Group>
  );
}
