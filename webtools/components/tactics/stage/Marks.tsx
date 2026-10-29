"use client";

// Playing: what effects draw along a move (lib/tactics/marks.ts). Dashed
// trails behind objects, dashed arrows ahead of them showing the way, and
// dashed rings in an object's colour, outlined in white. Drawn under the
// objects, never touched.
import { Arrow, Circle, Group, Line } from "react-konva";
import { PLAYER_RADIUS } from "../../../lib/tactics/ball.ts";
import type { Board } from "../../../lib/tactics/model.ts";
import type { Rendered } from "../../../lib/tactics/timeline.ts";

const DASH = [0.7, 0.5];

/** An object's own colour: a player's team colour unless it has its own; white for the ball. */
function colorOf(item: Rendered, board: Board): string {
  if (item.type === "player") return item.color ?? board.teams[item.side].color;
  return "color" in item && typeof item.color === "string" ? item.color : "#ffffff";
}

export function Marks({ objects, board }: { objects: Rendered[]; board: Board }) {
  const marked = objects.filter(item => item.trails || item.ring);
  if (marked.length === 0) return null;
  return (
    <Group listening={false}>
      {marked.flatMap(item => (item.trails ?? []).map((trail, index) => {
        const common = {
          points: trail.points, strokeWidth: 0.2, dash: DASH, lineCap: "round" as const, lineJoin: "round" as const,
          opacity: 0.85 * trail.opacity, listening: false, perfectDrawEnabled: false,
        };
        const color = item.type === "ball" ? "#fef08a" : "#ffffff";
        return trail.arrow
          ? <Arrow key={`${item.id}-${index}`} {...common} stroke={color} fill={color} strokeWidth={0.24} pointerLength={1.2} pointerWidth={1.1} />
          : <Line key={`${item.id}-${index}`} {...common} stroke={color} />;
      }))}
      {marked.filter(item => item.ring).map(item => {
        const radius = PLAYER_RADIUS * 1.75 * ("scale" in item && typeof item.scale === "number" ? item.scale : 1) * item.ring!.grow;
        return (
          <Group key={`${item.id}-ring`} x={item.x} y={item.y} opacity={item.ring!.opacity} listening={false}>
            <Circle radius={radius} stroke="#ffffff" strokeWidth={0.42} dash={DASH} listening={false} perfectDrawEnabled={false} />
            <Circle radius={radius} stroke={colorOf(item, board)} strokeWidth={0.22} dash={DASH} listening={false} perfectDrawEnabled={false} />
          </Group>
        );
      })}
    </Group>
  );
}
