"use client";

// Lines, passes, runs and dribbles: straight, or curved through a control
// point, with an arrowhead at the end or both, a dribble swinging from side
// to side; and freehand strokes. White shows in the theme's ink on a light pitch. A wide invisible
// hit area makes thin lines easy to take with a finger.
import { Arrow, Group, Line } from "react-konva";
import type { FreehandObject, LineObject } from "../../../lib/tactics/model.ts";
import { partialPolyline, sampleCurve, wavePoints } from "../../../lib/tactics/path.ts";
import { inkFor, type ThemeLook } from "../../../lib/tactics/pitch-style.ts";
import type { Rendered } from "../../../lib/tactics/timeline.ts";
import { nodeRef, useStage } from "../stage/stage-context.ts";
import { useObjectDrag } from "../stage/use-object-drag.ts";

const DASH = [1.1, 0.8];

/** The points drawn: a curve through the control point when bent. */
export function linePoints(item: LineObject): number[] {
  const [x1, y1, x2, y2] = item.points;
  return sampleCurve({ x: x1, y: y1 }, { x: x2, y: y2 }, item.control);
}

function Stroke({ points, arrow, dashed, color, width, tension, selected }: {
  points: number[]; arrow: "none" | "end" | "both"; dashed: boolean; color: string; width: number; tension: number; selected: boolean;
}) {
  const shared = useStage();
  const common = {
    points, stroke: color, strokeWidth: width, dash: dashed ? DASH : undefined, tension,
    lineCap: "round" as const, lineJoin: "round" as const,
    hitStrokeWidth: Math.max(2.4, shared.metresPerPixel() * 28),
    perfectDrawEnabled: false,
  };
  // Selected: a wide yellow line beneath. A canvas shadow would need a
  // buffer the size of the board, which fails when the board has no height.
  const halo = selected && <Line points={points} tension={tension} stroke="#facc15" strokeWidth={width + 0.7} opacity={0.6}
    lineCap="round" lineJoin="round" listening={false} perfectDrawEnabled={false} />;
  if (arrow === "none") return <>{halo}<Line {...common} /></>;
  return <>{halo}<Arrow {...common} fill={color} pointerLength={1.5} pointerWidth={1.4} pointerAtBeginning={arrow === "both"} /></>;
}

const shaped = (points: number[], wavy: boolean | undefined) => (wavy ? wavePoints(points) : points);

export function LineNode({ item, selected, look }: { item: LineObject & Rendered; selected: boolean; look: ThemeLook }) {
  const shared = useStage();
  const drag = useObjectDrag(item);
  return (
    <Group ref={nodeRef(shared, item.id)} x={item.x} y={item.y} opacity={item.opacity ?? 1} {...drag}>
      <Stroke points={shaped(partialPolyline(linePoints(item), item.drawn ?? 1), item.wavy)} arrow={item.arrow} dashed={item.dashed} color={inkFor(item.color, look)}
        width={item.width} tension={item.wavy ? 0.4 : 0} selected={selected} />
    </Group>
  );
}

export function FreehandNode({ item, selected, look }: { item: FreehandObject & Rendered; selected: boolean; look: ThemeLook }) {
  const shared = useStage();
  const drag = useObjectDrag(item);
  return (
    <Group ref={nodeRef(shared, item.id)} x={item.x} y={item.y} opacity={item.opacity ?? 1} {...drag}>
      <Stroke points={shaped(partialPolyline(item.points, item.drawn ?? 1), item.wavy)} arrow={item.arrow} dashed={item.dashed} color={inkFor(item.color, look)}
        width={item.width} tension={0.45} selected={selected} />
    </Group>
  );
}
