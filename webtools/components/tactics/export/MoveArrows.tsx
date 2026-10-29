"use client";

// A still picture's moves (lib/tactics/marks.ts movesInto): dashed arrows
// under the objects, in the pitch's ink for the players (white, or dark on a
// light pitch), yellow for the ball's passes.
import { Arrow, Group } from "react-konva";
import type { Trail } from "../../../lib/tactics/marks.ts";

/** ink: what white shows as on the board's pitch; light: the pitch is light, so the ball's yellow darkens. */
export function MoveArrows({ moves, ink = "#ffffff", light = false }: { moves: Trail[]; ink?: string; light?: boolean }) {
  if (moves.length === 0) return null;
  return (
    <Group listening={false}>
      {moves.map((move, index) => {
        const color = move.ball ? (light ? "#ca8a04" : "#fde047") : ink;
        return (
          <Arrow key={index} points={move.points} stroke={color} fill={color} strokeWidth={0.26} dash={[0.8, 0.55]}
            pointerLength={1.3} pointerWidth={1.2} lineCap="round" lineJoin="round" opacity={0.9} listening={false} perfectDrawEnabled={false} />
        );
      })}
    </Group>
  );
}
