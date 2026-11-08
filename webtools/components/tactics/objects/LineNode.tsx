"use client";

// Lines, passes, runs and dribbles: straight, or curved through a control
// point, with an arrowhead at the end or both, a dribble swinging from side
// to side; and freehand strokes. Drawn as on television (lib/tactics/ribbon.ts):
// a pass a band widening into a broad head, every mark edged and shadowed; a pass in the air arcs over
// its shadow on the ground. White shows in the theme's ink on a light pitch. A wide invisible
// hit area makes thin lines easy to take with a finger. With measuring on,
// a line shows how long it is.
import { useEffect, useState } from "react";
import { Group, Line } from "react-konva";
import { halfway, metres, pathLength } from "../../../lib/tactics/measure.ts";
import type { ArrowHead, FreehandObject, LineObject, Point } from "../../../lib/tactics/model.ts";
import { arrowHeads, band, edgeFor, shortened } from "../../../lib/tactics/ribbon.ts";
import { airPoints, partialPolyline, sampleCurve, wavePoints } from "../../../lib/tactics/path.ts";
import { inkFor, type ThemeLook } from "../../../lib/tactics/pitch-style.ts";
import type { Rendered } from "../../../lib/tactics/timeline.ts";
import { nodeRef, objectDrag, objectDrop, useStage } from "../stage/stage-context.ts";
import { startAt } from "../../../lib/tactics/line-attach.ts";
import { useObjectDrag } from "../stage/use-object-drag.ts";
import { MeasureTag } from "./MeasureTag.tsx";

const DASH = [1.1, 0.8];
/** Where a mark's shadow falls. */
const SHADOW = { x: 0.16, y: 0.26 };

/** The points drawn: a curve through the control point when bent. */
export function linePoints(item: LineObject): number[] {
  const [x1, y1, x2, y2] = item.points;
  return sampleCurve({ x: x1, y: y1 }, { x: x2, y: y2 }, item.control);
}

/** ground: a pass in the air's shadow, the way it takes along the ground under its arc. */
function Stroke({ points, arrow, dashed, wavy, color, width, tension, selected, ground }: {
  points: number[]; arrow: ArrowHead; dashed: boolean; wavy: boolean; color: string; width: number; tension: number; selected: boolean; ground?: number[];
}) {
  const shared = useStage();
  const edge = edgeFor(color);
  const hit = Math.max(2.4, shared.metresPerPixel() * 28);
  // A pass: one flat band widening into its arrowhead, edged and lying on a
  // soft shadow. A canvas shadow would need a buffer the size of the board,
  // which fails when the board has no height; an offset copy does the same.
  if (!dashed && !wavy && arrow !== "none") {
    const outline = band(points, width, arrow);
    if (outline.length < 6) return null;
    const shape = { points: outline, closed: true, lineJoin: "round" as const, perfectDrawEnabled: false };
    return (
      <>
        {ground
          ? <Line points={ground} stroke="rgba(0,0,0,0.32)" strokeWidth={width * 1.4} lineCap="round" lineJoin="round" listening={false} perfectDrawEnabled={false} />
          : <Line {...shape} x={SHADOW.x} y={SHADOW.y} fill="rgba(0,0,0,0.24)" listening={false} />}
        {selected && <Line {...shape} stroke="#facc15" strokeWidth={0.7} opacity={0.6} listening={false} />}
        <Line {...shape} fill={color} stroke={edge} strokeWidth={0.12} hitStrokeWidth={hit} />
      </>
    );
  }
  // A run, a dribble or a line without a head: a stroke edged in a wider one beneath, the heads filled.
  const line = shortened(points, width, arrow);
  const heads = arrow === "none" ? [] : arrowHeads(points, width, arrow === "both");
  const common = { points: line, tension, lineCap: "round" as const, lineJoin: "round" as const, dash: dashed ? DASH : undefined, perfectDrawEnabled: false };
  return (
    <>
      <Line {...common} x={SHADOW.x} y={SHADOW.y} stroke="rgba(0,0,0,0.24)" strokeWidth={width} listening={false} />
      {heads.map((head, index) => <Line key={`s${index}`} points={head} closed x={SHADOW.x} y={SHADOW.y} fill="rgba(0,0,0,0.24)" listening={false} perfectDrawEnabled={false} />)}
      {selected && <Line {...common} dash={undefined} stroke="#facc15" strokeWidth={width + 0.7} opacity={0.6} listening={false} />}
      <Line {...common} stroke={edge} strokeWidth={width + 0.16} listening={false} />
      <Line {...common} stroke={color} strokeWidth={width} hitStrokeWidth={hit} />
      {heads.map((head, index) => <Line key={`h${index}`} points={head} closed fill={color} stroke={edge} strokeWidth={0.1} lineJoin="round" hitStrokeWidth={hit} perfectDrawEnabled={false} />)}
    </>
  );
}

const shaped = (points: number[], wavy: boolean | undefined) => (wavy ? wavePoints(points) : points);

/** A line's length, tagged halfway along it. */
function Length({ points, upright }: { points: number[]; upright: number }) {
  const path: Point[] = [];
  for (let index = 0; index + 1 < points.length; index += 2) path.push({ x: points[index], y: points[index + 1] });
  if (path.length < 2) return null;
  return <MeasureTag at={halfway(path)} text={metres(pathLength(path, false))} upright={upright} />;
}

type Measured = { measure?: boolean; upright?: number };

export function LineNode({ item, selected, look, measure = false, upright = 0 }: { item: LineObject & Rendered; selected: boolean; look: ThemeLook } & Measured) {
  const shared = useStage();
  const drag = useObjectDrag(item);
  // Stuck to a player being dragged: the start follows them before the drop is written.
  const [following, setFollowing] = useState<Point | null>(null);
  useEffect(() => {
    const from = item.from;
    if (!from) return;
    const moving = (moves: Record<string, Point>) => { if (from in moves && !(item.id in moves)) setFollowing(moves[from]); };
    const dropped = () => setFollowing(null);
    objectDrag.add(moving);
    objectDrop.add(dropped);
    return () => { objectDrag.delete(moving); objectDrop.delete(dropped); };
  }, [item.from, item.id]);
  const line = following ? startAt(item, following) : item;
  const way = linePoints(line);
  // In the air: the pass arcs over its shadow, which runs the way along the ground.
  const air = !!item.aerial && !item.dashed && !item.wavy && item.arrow !== "none";
  const drawn = item.drawn ?? 1;
  return (
    <Group ref={nodeRef(shared, item.id)} x={line.x} y={line.y} opacity={item.opacity ?? 1} {...drag}>
      <Stroke points={air ? partialPolyline(airPoints(way), drawn) : shaped(partialPolyline(way, drawn), item.wavy)} arrow={item.arrow} dashed={item.dashed} wavy={!!item.wavy} color={inkFor(item.color, look)}
        width={item.width} tension={item.wavy ? 0.4 : 0} selected={selected} ground={air ? partialPolyline(way, drawn) : undefined} />
      {measure && <Length points={way} upright={upright} />}
    </Group>
  );
}

export function FreehandNode({ item, selected, look, measure = false, upright = 0 }: { item: FreehandObject & Rendered; selected: boolean; look: ThemeLook } & Measured) {
  const shared = useStage();
  const drag = useObjectDrag(item);
  return (
    <Group ref={nodeRef(shared, item.id)} x={item.x} y={item.y} opacity={item.opacity ?? 1} {...drag}>
      <Stroke points={shaped(partialPolyline(item.points, item.drawn ?? 1), item.wavy)} arrow={item.arrow} dashed={item.dashed} wavy={!!item.wavy} color={inkFor(item.color, look)}
        width={item.width} tension={0.45} selected={selected} />
      {measure && <Length points={item.points} upright={upright} />}
    </Group>
  );
}
