"use client";

// Playing: the dashed trails objects with the trail effect leave behind, so
// the eye sees where they came from. Drawn under the objects, never touched.
import { Group, Line } from "react-konva";
import type { Rendered } from "../../../lib/tactics/timeline.ts";

export function Trails({ objects }: { objects: Rendered[] }) {
  const trails = objects.flatMap(item => (item.trails ?? []).map((trail, index) => ({ key: `${item.id}-${index}`, ball: item.type === "ball", ...trail })));
  if (trails.length === 0) return null;
  return (
    <Group listening={false}>
      {trails.map(trail => (
        <Line key={trail.key} points={trail.points} stroke={trail.ball ? "#fef08a" : "#ffffff"} strokeWidth={0.2} dash={[0.7, 0.5]}
          lineCap="round" lineJoin="round" opacity={0.85 * trail.opacity} listening={false} perfectDrawEnabled={false} />
      ))}
    </Group>
  );
}
