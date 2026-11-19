"use client";

// A zone of one's own shape (lib/tactics/zone.ts): filled or striped inside
// its edge, edged and glowing as the other areas are. Dragged as one;
// selected on a board being edited, each corner has a handle to drag on its
// own, and each side one in its middle that bends it, as an arrow is bent; a
// double tap there makes the side straight again. Ctrl-clicking the edge, or
// a long press on it, puts a corner there; Alt-clicking a corner, or a long
// press on it, takes it away. With measuring on it shows the ground it covers.
import { useRef, useState } from "react";
import type { Context } from "konva/lib/Context";
import type { KonvaEventObject } from "konva/lib/Node";
import { Circle, Group, Line } from "react-konva";
import { polygonArea, squareMetres } from "../../../lib/tactics/measure.ts";
import type { Point, ZoneObject } from "../../../lib/tactics/model.ts";
import type { Rendered } from "../../../lib/tactics/timeline.ts";
import { bendSide, bendsAfterCorner, cornersOf, insertCorner, moveCorner, nearestOnEdge, removeCorner, sideMiddle, zoneOutline } from "../../../lib/tactics/zone.ts";
import { useEditor } from "../store.ts";
import { nodeRef, useStage } from "../stage/stage-context.ts";
import { useObjectDrag } from "../stage/use-object-drag.ts";
import { AreaFill } from "./AreaFill.tsx";
import { look } from "./look.tsx";
import { MeasureTag } from "./MeasureTag.tsx";

/** A corner or a side's middle being dragged, before the drop is written. */
type Moving = { kind: "corner" | "side"; index: number; at: Point };

/** The zone's corners and bends with what is being dragged applied. */
function shaped(item: ZoneObject, moving: Moving | null): Pick<ZoneObject, "points" | "bends"> {
  if (!moving) return item;
  if (moving.kind === "side") return { points: item.points, bends: bendSide(item, moving.index, moving.at) };
  return { points: moveCorner(item, moving.index, moving.at), bends: bendsAfterCorner(item, moving.index, moving.at) };
}

const pointOf = (event: KonvaEventObject<DragEvent>) => ({ x: event.target.x(), y: event.target.y() });
/** How long a finger is held still on the edge to put a corner there, in ms. */
const LONG_PRESS = 500;

/** A handle's own press and drag, never the zone's. */
const own = (event: KonvaEventObject<Event>) => { event.cancelBubble = true; };

export function ZoneNode({ item, selected, measure = false, upright = 0 }: { item: ZoneObject & Rendered; selected: boolean; measure?: boolean; upright?: number }) {
  const shared = useStage();
  const drag = useObjectDrag(item);
  const [moving, setMoving] = useState<Moving | null>(null);
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
  const write = (changes: Partial<ZoneObject>) => { useEditor.getState().patch({ [item.id]: changes }); setMoving(null); };
  const straighten = (side: number) => write({ bends: bendSide(item, side, null) });
  /** Where the pointer is on the edge, if it is near enough to it. */
  const onEdge = (target: KonvaEventObject<Event>["target"]) => {
    const at = target.getRelativePointerPosition();
    return at && nearestOnEdge(item, at).distance <= handle * 2 ? at : null;
  };
  const letGo = () => { if (press.current) clearTimeout(press.current); press.current = null; };
  // Ctrl or Cmd held, a press on the edge puts a corner rather than moving the zone.
  const edgeMouseDown = (event: KonvaEventObject<MouseEvent>) => {
    const at = event.evt.ctrlKey || event.evt.metaKey ? onEdge(event.target) : null;
    if (!at) return;
    own(event);
    event.evt.preventDefault();
    write(insertCorner(item, at));
  };
  const takeCorner = (index: number) => { const fewer = removeCorner(item, index); if (fewer) write(fewer); };
  // A finger held still on a corner: that corner away. Moved, it drags the corner.
  const cornerTouchStart = (event: KonvaEventObject<TouchEvent>, index: number) => {
    own(event);
    letGo();
    if (event.evt.touches.length > 1 || corners.length <= 3) return;
    const node = event.target;
    press.current = setTimeout(() => { press.current = null; if (!node.isDragging()) takeCorner(index); }, LONG_PRESS);
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
      if (!group?.isDragging()) write(insertCorner(item, at));
    }, LONG_PRESS);
  };
  return (
    <Group ref={nodeRef(shared, item.id)} x={item.x} y={item.y} rotation={item.rotation} {...look(item)} {...drag}>
      {/* Lit, the zone is the pitch left clear, the dimming round it drawn under everything (stage/ZoneDim.tsx). */}
      {!item.dim && <AreaFill box={box} outline={outline} color={item.color} fill={item.fill} pattern={item.pattern} />}
      {/* A soft glow outside the edge, as television marks an area. */}
      <Line {...line} stroke={item.color} strokeWidth={0.8} opacity={0.25} listening={false} />
      <Line {...line} stroke={item.color} strokeWidth={0.25} dash={item.dashed ? [0.9, 0.6] : undefined} fill="rgba(0,0,0,0)"
        {...(editable ? { hitStrokeWidth: handle * 2.5, onMouseDown: edgeMouseDown, onTouchStart: edgeTouchStart, onTouchMove: letGo, onTouchEnd: letGo } : {})} />
      {measure && <MeasureTag at={middle} text={squareMetres(polygonArea(edge))} upright={upright} turn={item.rotation} />}
      {editable && corners.map((_, side) => {
        const at = sideMiddle(shape, side);
        const bent = !!shape.bends?.[side];
        return (
          <Circle key={`side-${side}`} x={at.x} y={at.y} radius={handle * 0.8} fill={bent ? "#ffffff" : "rgba(255,255,255,0.6)"} stroke="#111827" strokeWidth={handle * 0.2} draggable
            onMouseDown={own} onTouchStart={own} onDragStart={own}
            onDragMove={event => { own(event); setMoving({ kind: "side", index: side, at: pointOf(event) }); }}
            onDragEnd={event => { own(event); write({ bends: bendSide(item, side, pointOf(event)) }); }}
            onDblClick={event => { own(event); straighten(side); }} onDblTap={event => { own(event); straighten(side); }} />
        );
      })}
      {editable && corners.map((corner, index) => (
        <Circle key={`corner-${index}`} x={corner.x} y={corner.y} radius={handle} fill="#ffffff" stroke="#111827" strokeWidth={handle * 0.25} draggable
          onMouseDown={event => {
            own(event);
            if (!event.evt.altKey) return;
            event.evt.preventDefault();
            event.target.stopDrag();
            takeCorner(index);
          }}
          onTouchStart={event => cornerTouchStart(event, index)} onTouchEnd={letGo} onDragStart={event => { own(event); letGo(); }}
          onDragMove={event => { own(event); setMoving({ kind: "corner", index, at: pointOf(event) }); }}
          onDragEnd={event => {
            own(event);
            const at = pointOf(event);
            write({ points: moveCorner(item, index, at), bends: bendsAfterCorner(item, index, at) });
          }} />
      ))}
    </Group>
  );
}
