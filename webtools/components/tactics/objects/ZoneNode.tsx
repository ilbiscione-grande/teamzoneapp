"use client";

// A zone of one's own shape (lib/tactics/zone.ts): filled or striped inside
// its edge, edged and glowing as the other areas are; lit, left clear with
// the pitch round it dimmed (stage/ZoneDim.tsx). Dragged as one; selected on
// a board being edited, its handles (ZoneHandles, drawn over everything)
// change its corners and sides, and Ctrl-clicking the edge, or a long press
// on it, puts a corner there. With measuring on it shows the ground it covers.
import { useRef } from "react";
import type { Context } from "konva/lib/Context";
import type { KonvaEventObject } from "konva/lib/Node";
import { Group, Line } from "react-konva";
import { polygonArea, squareMetres } from "../../../lib/tactics/measure.ts";
import type { ZoneObject } from "../../../lib/tactics/model.ts";
import type { Rendered } from "../../../lib/tactics/timeline.ts";
import { bendSide, bendsAfterCorner, cornersOf, insertCorner, moveCorner, nearestOnEdge, zoneOutline } from "../../../lib/tactics/zone.ts";
import { useEditor } from "../store.ts";
import { nodeRef, useStage } from "../stage/stage-context.ts";
import { useObjectDrag } from "../stage/use-object-drag.ts";
import { AreaFill } from "./AreaFill.tsx";
import { look } from "./look.tsx";
import { MeasureTag } from "./MeasureTag.tsx";
import { useZoneMoving, type Moving } from "./zone-moving.ts";

/** The zone's corners and bends with what is being dragged applied. */
export function shaped(item: ZoneObject, moving: Moving | null): Pick<ZoneObject, "points" | "bends"> {
  if (!moving) return item;
  if (moving.kind === "side") return { points: item.points, bends: bendSide(item, moving.index, moving.at) };
  return { points: moveCorner(item, moving.index, moving.at), bends: bendsAfterCorner(item, moving.index, moving.at) };
}

/** How long a finger is held still to put or take a corner, in ms. */
export const LONG_PRESS = 500;

/** A handle's own press and drag, never the zone's. */
export const own = (event: KonvaEventObject<Event>) => { event.cancelBubble = true; };

export function ZoneNode({ item, selected, measure = false, upright = 0 }: { item: ZoneObject & Rendered; selected: boolean; measure?: boolean; upright?: number }) {
  const shared = useStage();
  const drag = useObjectDrag(item);
  const moving = useZoneMoving(state => (state.moving?.id === item.id ? state.moving : null));
  const press = useRef<ReturnType<typeof setTimeout> | null>(null);
  const shape = shaped(item, moving);
  const corners = cornersOf(shape);
  if (corners.length < 3) return null;
  const edge = zoneOutline(shape);
  const xs = edge.map(point => point.x), ys = edge.map(point => point.y);
  const box = { x: Math.min(...xs), y: Math.min(...ys), width: Math.max(...xs) - Math.min(...xs), height: Math.max(...ys) - Math.min(...ys) };
  const outline = (context: Context) => {
    context.beginPath();
    edge.forEach((point, index) => (index === 0 ? context.moveTo(point.x, point.y) : context.lineTo(point.x, point.y)));
    context.closePath();
  };
  const middle = { x: corners.reduce((sum, point) => sum + point.x, 0) / corners.length, y: corners.reduce((sum, point) => sum + point.y, 0) / corners.length };
  const line = { points: edge.flatMap(point => [point.x, point.y]), closed: true, lineJoin: "round" as const, perfectDrawEnabled: false };
  const handle = shared.metresPerPixel() * 7;
  const editable = selected && shared.editable && !item.locked;
  /** Where the pointer is on the edge, if it is near enough to it. */
  const onEdge = (target: KonvaEventObject<Event>["target"]) => {
    const at = target.getRelativePointerPosition();
    return at && nearestOnEdge(item, at).distance <= handle * 2 ? at : null;
  };
  const put = (at: { x: number; y: number }) => useEditor.getState().patch({ [item.id]: insertCorner(item, at) });
  const letGo = () => { if (press.current) clearTimeout(press.current); press.current = null; };
  // Ctrl or Cmd held, a press on the edge puts a corner rather than moving the zone.
  const edgeMouseDown = (event: KonvaEventObject<MouseEvent>) => {
    const at = event.evt.ctrlKey || event.evt.metaKey ? onEdge(event.target) : null;
    if (!at) return;
    own(event);
    event.evt.preventDefault();
    put(at);
  };
  // A finger held still on the edge: a corner there. Moved, it drags the zone as ever.
  const edgeTouchStart = (event: KonvaEventObject<TouchEvent>) => {
    letGo();
    if (event.evt.touches.length > 1) return;
    const at = onEdge(event.target);
    if (!at) return;
    const group = event.target.getParent();
    press.current = setTimeout(() => {
      press.current = null;
      if (!group?.isDragging()) put(at);
    }, LONG_PRESS);
  };
  return (
    <Group ref={nodeRef(shared, item.id)} x={item.x} y={item.y} rotation={item.rotation} {...look(item)} {...drag}>
      {!item.dim && <AreaFill box={box} outline={outline} color={item.color} fill={item.fill} pattern={item.pattern} />}
      {/* A soft glow outside the edge, as television marks an area. */}
      {!item.dim && <Line {...line} stroke={item.color} strokeWidth={0.8} opacity={0.25} listening={false} />}
      {/* Lit, the edge is still there to be pressed, unseen: the dimming shows it when selected. */}
      <Line {...line} stroke={item.dim ? "rgba(0,0,0,0)" : item.color} strokeWidth={0.25} dash={item.dashed ? [0.9, 0.6] : undefined} fill="rgba(0,0,0,0)"
        {...(editable ? { hitStrokeWidth: handle * 2.5, onMouseDown: edgeMouseDown, onTouchStart: edgeTouchStart, onTouchMove: letGo, onTouchEnd: letGo } : {})} />
      {measure && <MeasureTag at={middle} text={squareMetres(polygonArea(edge))} upright={upright} turn={item.rotation} />}
    </Group>
  );
}
