"use client";

// The ruler's measure: a line from one point to another with a tick at each
// end and the distance halfway, in metres. Shown while measuring, never saved.
import { Group, Line } from "react-konva";
import { distance, metres } from "../../../lib/tactics/measure.ts";
import type { Point } from "../../../lib/tactics/model.ts";
import { MeasureTag } from "../objects/MeasureTag.tsx";

const TICK = 0.9;

export function RulerNode({ from, to, upright }: { from: Point; to: Point; upright: number }) {
  const length = distance(from, to) || 1;
  // Across the line, for the ticks.
  const across = { x: (-(to.y - from.y) / length) * TICK, y: ((to.x - from.x) / length) * TICK };
  const tick = (at: Point) => [at.x - across.x, at.y - across.y, at.x + across.x, at.y + across.y];
  return (
    <Group listening={false}>
      <Line points={[from.x, from.y, to.x, to.y]} stroke="#0f1726" strokeWidth={0.45} opacity={0.5} />
      <Line points={[from.x, from.y, to.x, to.y]} stroke="#facc15" strokeWidth={0.22} dash={[0.8, 0.5]} />
      <Line points={tick(from)} stroke="#facc15" strokeWidth={0.25} />
      <Line points={tick(to)} stroke="#facc15" strokeWidth={0.25} />
      <MeasureTag at={{ x: (from.x + to.x) / 2, y: (from.y + to.y) / 2 }} text={metres(distance(from, to))} upright={upright} />
    </Group>
  );
}
