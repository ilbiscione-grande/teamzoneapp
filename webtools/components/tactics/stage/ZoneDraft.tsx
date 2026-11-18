"use client";

// A zone being drawn corner by corner (use-zone-draw.ts): the corners so far
// joined, a dashed line on to the pointer, and the first corner larger, as
// the place to tap to close it.
import { Circle, Group, Line } from "react-konva";
import type { Point } from "../../../lib/tactics/model.ts";

const COLOR = "#facc15";

/** pixel: metres per screen pixel. */
export function ZoneDraft({ corners, hover, pixel }: { corners: Point[]; hover: Point | null; pixel: number }) {
  const flat = corners.flatMap(point => [point.x, point.y]);
  const last = corners[corners.length - 1];
  return (
    <Group listening={false}>
      {corners.length > 2 && <Line points={flat} closed fill="rgba(250,204,21,0.18)" perfectDrawEnabled={false} />}
      <Line points={flat} stroke={COLOR} strokeWidth={pixel * 2.5} lineJoin="round" lineCap="round" perfectDrawEnabled={false} />
      {hover && last && <Line points={[last.x, last.y, hover.x, hover.y]} stroke={COLOR} strokeWidth={pixel * 2} dash={[pixel * 8, pixel * 6]} perfectDrawEnabled={false} />}
      {corners.map((corner, index) => (
        <Circle key={index} x={corner.x} y={corner.y} radius={pixel * (index === 0 && corners.length > 2 ? 9 : 5)}
          fill={index === 0 ? COLOR : "#ffffff"} stroke="#111827" strokeWidth={pixel * 1.5} perfectDrawEnabled={false} />
      ))}
    </Group>
  );
}
