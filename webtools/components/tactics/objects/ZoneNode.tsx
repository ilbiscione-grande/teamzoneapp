"use client";

// A zone of one's own shape (lib/tactics/zone.ts): filled or striped inside
// its corners, edged and glowing as the other areas are. Dragged as one;
// selected on a board being edited, each corner has a handle to drag on its
// own. With measuring on it shows the ground it covers.
import { useState } from "react";
import type { Context } from "konva/lib/Context";
import { Circle, Group, Line } from "react-konva";
import { polygonArea, squareMetres } from "../../../lib/tactics/measure.ts";
import type { Point, ZoneObject } from "../../../lib/tactics/model.ts";
import type { Rendered } from "../../../lib/tactics/timeline.ts";
import { cornersOf, moveCorner } from "../../../lib/tactics/zone.ts";
import { useEditor } from "../store.ts";
import { nodeRef, useStage } from "../stage/stage-context.ts";
import { useObjectDrag } from "../stage/use-object-drag.ts";
import { AreaFill } from "./AreaFill.tsx";
import { look } from "./look.tsx";
import { MeasureTag } from "./MeasureTag.tsx";

export function ZoneNode({ item, selected, measure = false, upright = 0 }: { item: ZoneObject & Rendered; selected: boolean; measure?: boolean; upright?: number }) {
  const shared = useStage();
  const drag = useObjectDrag(item);
  // A corner being dragged, before the drop is written.
  const [moving, setMoving] = useState<{ index: number; at: Point } | null>(null);
  const points = moving ? moveCorner(item, moving.index, moving.at) : item.points;
  const corners = cornersOf({ points });
  if (corners.length < 3) return null;
  const xs = corners.map(point => point.x), ys = corners.map(point => point.y);
  const box = { x: Math.min(...xs), y: Math.min(...ys), width: Math.max(...xs) - Math.min(...xs), height: Math.max(...ys) - Math.min(...ys) };
  const outline = (context: Context) => {
    context.beginPath();
    corners.forEach((point, index) => (index === 0 ? context.moveTo(point.x, point.y) : context.lineTo(point.x, point.y)));
    context.closePath();
  };
  const middle = { x: xs.reduce((sum, x) => sum + x, 0) / xs.length, y: ys.reduce((sum, y) => sum + y, 0) / ys.length };
  const line = { points, closed: true, lineJoin: "round" as const, perfectDrawEnabled: false };
  const handle = shared.metresPerPixel() * 7;
  const editable = selected && shared.editable && !item.locked;
  const cornerAt = (event: { target: { x: () => number; y: () => number } }) => ({ x: event.target.x(), y: event.target.y() });
  return (
    <Group ref={nodeRef(shared, item.id)} x={item.x} y={item.y} rotation={item.rotation} {...look(item)} {...drag}>
      <AreaFill box={box} outline={outline} color={item.color} fill={item.fill} pattern={item.pattern} />
      {/* A soft glow outside the edge, as television marks an area. */}
      <Line {...line} stroke={item.color} strokeWidth={0.8} opacity={0.25} listening={false} />
      <Line {...line} stroke={item.color} strokeWidth={0.25} dash={item.dashed ? [0.9, 0.6] : undefined} fill="rgba(0,0,0,0)" />
      {measure && <MeasureTag at={middle} text={squareMetres(polygonArea(corners))} upright={upright} turn={item.rotation} />}
      {editable && corners.map((corner, index) => (
        <Circle key={index} x={corner.x} y={corner.y} radius={handle} fill="#ffffff" stroke="#111827" strokeWidth={handle * 0.25} draggable
          onMouseDown={event => { event.cancelBubble = true; }} onTouchStart={event => { event.cancelBubble = true; }}
          onDragStart={event => { event.cancelBubble = true; }}
          onDragMove={event => { event.cancelBubble = true; setMoving({ index, at: cornerAt(event) }); }}
          onDragEnd={event => {
            event.cancelBubble = true;
            useEditor.getState().patch({ [item.id]: { points: moveCorner(item, index, cornerAt(event)) } });
            setMoving(null);
          }} />
      ))}
    </Group>
  );
}
