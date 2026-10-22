"use client";

// Lines, passes and runs: straight, or curved through a control point, with
// an arrowhead at the end or both; and freehand strokes. A wide invisible
// hit area makes thin lines easy to take with a finger.
import { Arrow, Group, Line } from "react-konva";
import type { FreehandObject, LineObject } from "../../../lib/tactics/model.ts";
import { nodeRef, useStage } from "../stage/stage-context.ts";
import { useObjectDrag } from "../stage/use-object-drag.ts";

const DASH = [1.1, 0.8];

/** The points drawn: through the control point when curved. */
export function linePoints(item: LineObject): number[] {
  const [x1, y1, x2, y2] = item.points;
  return item.control ? [x1, y1, item.control.x, item.control.y, x2, y2] : [x1, y1, x2, y2];
}

function Stroke({ points, arrow, dashed, color, width, tension, selected }: {
  points: number[]; arrow: "none" | "end" | "both"; dashed: boolean; color: string; width: number; tension: number; selected: boolean;
}) {
  const shared = useStage();
  const common = {
    points, stroke: color, strokeWidth: width, dash: dashed ? DASH : undefined, tension,
    lineCap: "round" as const, lineJoin: "round" as const,
    hitStrokeWidth: Math.max(2.4, shared.metresPerPixel() * 28),
    shadowColor: selected ? "#facc15" : undefined, shadowBlur: selected ? 0.8 : 0, shadowOpacity: selected ? 1 : 0,
  };
  if (arrow === "none") return <Line {...common} />;
  return <Arrow {...common} fill={color} pointerLength={1.5} pointerWidth={1.4} pointerAtBeginning={arrow === "both"} />;
}

export function LineNode({ item, selected }: { item: LineObject; selected: boolean }) {
  const shared = useStage();
  const drag = useObjectDrag(item);
  return (
    <Group ref={nodeRef(shared, item.id)} x={item.x} y={item.y} {...drag}>
      <Stroke points={linePoints(item)} arrow={item.arrow} dashed={item.dashed} color={item.color} width={item.width}
        tension={item.control ? 0.5 : 0} selected={selected} />
    </Group>
  );
}

export function FreehandNode({ item, selected }: { item: FreehandObject; selected: boolean }) {
  const shared = useStage();
  const drag = useObjectDrag(item);
  return (
    <Group ref={nodeRef(shared, item.id)} x={item.x} y={item.y} {...drag}>
      <Stroke points={item.points} arrow={item.arrow} dashed={item.dashed} color={item.color} width={item.width}
        tension={0.45} selected={selected} />
    </Group>
  );
}
