"use client";

// Playing: what effects draw along a move (lib/tactics/marks.ts). Dashed
// trails behind objects, arrows ahead of them showing the way (drawn as a
// pass is), and rings in an object's colour at its feet, edged in white. Drawn under the
// objects, never touched.
import { Circle, Group, Line } from "react-konva";
import { PLAYER_RADIUS } from "../../../lib/tactics/ball.ts";
import type { Board } from "../../../lib/tactics/model.ts";
import { lookOf } from "../../../lib/tactics/pitch-style.ts";
import { band, edgeFor } from "../../../lib/tactics/ribbon.ts";
import type { Rendered } from "../../../lib/tactics/timeline.ts";
import { alpha } from "../objects/AreaFill.tsx";

const DASH = [0.7, 0.5];

/** An object's own colour: a player's team colour unless it has its own; white for the ball. */
function colorOf(item: Rendered, board: Board): string {
  if (item.type === "player") return item.color ?? board.teams[item.side].color;
  return "color" in item && typeof item.color === "string" ? item.color : "#ffffff";
}

export function Marks({ objects, board }: { objects: Rendered[]; board: Board }) {
  const marked = objects.filter(item => item.trails || item.ring);
  if (marked.length === 0) return null;
  const look = lookOf(board.pitch);
  return (
    <Group listening={false}>
      {marked.flatMap(item => (item.trails ?? []).map((trail, index) => {
        const common = {
          points: trail.points, strokeWidth: 0.2, dash: DASH, lineCap: "round" as const, lineJoin: "round" as const,
          opacity: 0.85 * trail.opacity, listening: false, perfectDrawEnabled: false,
        };
        const color = item.type === "ball" ? (look.light ? "#ca8a04" : "#fef08a") : look.ink;
        if (trail.arrow) {
          // The way ahead as a pass is drawn: a band widening into its head, edged and shadowed.
          const outline = band(trail.points, 0.3, "end");
          if (outline.length < 6) return null;
          return (
            <Group key={`${item.id}-${index}`} opacity={0.9 * trail.opacity} listening={false}>
              <Line points={outline} closed x={0.16} y={0.26} fill="rgba(0,0,0,0.22)" listening={false} perfectDrawEnabled={false} />
              <Line points={outline} closed fill={color} stroke={edgeFor(color)} strokeWidth={0.1} lineJoin="round" listening={false} perfectDrawEnabled={false} />
            </Group>
          );
        }
        return <Line key={`${item.id}-${index}`} {...common} stroke={color} />;
      }))}
      {marked.filter(item => item.ring).map(item => {
        const color = colorOf(item, board);
        const radius = PLAYER_RADIUS * 1.75 * ("scale" in item && typeof item.scale === "number" ? item.scale : 1) * item.ring!.grow;
        return (
          <Group key={`${item.id}-ring`} x={item.x} y={item.y} opacity={item.ring!.opacity} listening={false}>
            <Circle radius={radius} fill={alpha(color, 0.22)} stroke={look.light ? look.ink : "#ffffff"} strokeWidth={0.5} listening={false} perfectDrawEnabled={false} />
            <Circle radius={radius} stroke={color} strokeWidth={0.3} listening={false} perfectDrawEnabled={false} />
            <Circle radius={radius + 0.55} stroke={color} strokeWidth={0.12} opacity={0.6} listening={false} perfectDrawEnabled={false} />
          </Group>
        );
      })}
    </Group>
  );
}
