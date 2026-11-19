"use client";

// The handles of a selected zone (ZoneNode) on a board being edited, drawn
// over everything, a lit zone's dimming too: each corner one to drag on its
// own, Alt-clicked or long pressed to take it away; each side one in its
// middle that bends it, as an arrow is bent, double tapped to straighten.
// They follow the zone as it is dragged.
import type Konva from "konva";
import type { KonvaEventObject } from "konva/lib/Node";
import { useEffect, useRef } from "react";
import { Circle, Group } from "react-konva";
import type { ZoneObject } from "../../../lib/tactics/model.ts";
import { bendSide, bendsAfterCorner, cornersOf, moveCorner, removeCorner, sideMiddle } from "../../../lib/tactics/zone.ts";
import { useEditor } from "../store.ts";
import { useStage } from "../stage/stage-context.ts";
import { useZoneMoving } from "./zone-moving.ts";
import { LONG_PRESS, own, shaped } from "./ZoneNode.tsx";

const pointOf = (event: KonvaEventObject<DragEvent>) => ({ x: event.target.x(), y: event.target.y() });

export function ZoneHandles({ item }: { item: ZoneObject }) {
  const shared = useStage();
  const group = useRef<Konva.Group>(null);
  const press = useRef<ReturnType<typeof setTimeout> | null>(null);
  const moving = useZoneMoving(state => (state.moving?.id === item.id ? state.moving : null));
  const setMoving = useZoneMoving(state => state.set);

  // Dragged, the zone's node moves before anything is written: the handles go with it.
  useEffect(() => {
    const node = shared.nodes.get(item.id);
    if (!node) return;
    const follow = () => { group.current?.setAttrs({ x: node.x(), y: node.y(), rotation: node.rotation() }); };
    node.on("xChange.zoneHandles yChange.zoneHandles rotationChange.zoneHandles", follow);
    return () => { node.off(".zoneHandles"); };
  }, [shared, item.id]);

  if (!shared.editable || item.locked) return null;
  const shape = shaped(item, moving);
  const corners = cornersOf(shape);
  if (corners.length < 3) return null;
  const handle = shared.metresPerPixel() * 7;
  const write = (changes: Partial<ZoneObject>) => { useEditor.getState().patch({ [item.id]: changes }); setMoving(null); };
  const letGo = () => { if (press.current) clearTimeout(press.current); press.current = null; };
  const takeCorner = (index: number) => { const fewer = removeCorner(item, index); if (fewer) write(fewer); };
  // A finger held still on a corner: that corner away. Moved, it drags the corner.
  const cornerTouchStart = (event: KonvaEventObject<TouchEvent>, index: number) => {
    own(event);
    letGo();
    if (event.evt.touches.length > 1 || corners.length <= 3) return;
    const node = event.target;
    press.current = setTimeout(() => { press.current = null; if (!node.isDragging()) takeCorner(index); }, LONG_PRESS);
  };
  const straighten = (side: number) => write({ bends: bendSide(item, side, null) });
  return (
    <Group ref={group} x={item.x} y={item.y} rotation={item.rotation}>
      {corners.map((_, side) => {
        const at = sideMiddle(shape, side);
        const bent = !!shape.bends?.[side];
        return (
          <Circle key={`side-${side}`} x={at.x} y={at.y} radius={handle * 0.8} fill={bent ? "#ffffff" : "rgba(255,255,255,0.6)"} stroke="#111827" strokeWidth={handle * 0.2} draggable
            onMouseDown={own} onTouchStart={own} onDragStart={own}
            onDragMove={event => { own(event); setMoving({ id: item.id, kind: "side", index: side, at: pointOf(event) }); }}
            onDragEnd={event => { own(event); write({ bends: bendSide(item, side, pointOf(event)) }); }}
            onDblClick={event => { own(event); straighten(side); }} onDblTap={event => { own(event); straighten(side); }} />
        );
      })}
      {corners.map((corner, index) => (
        <Circle key={`corner-${index}`} x={corner.x} y={corner.y} radius={handle} fill="#ffffff" stroke="#111827" strokeWidth={handle * 0.25} draggable
          onMouseDown={event => {
            own(event);
            if (!event.evt.altKey) return;
            event.evt.preventDefault();
            event.target.stopDrag();
            takeCorner(index);
          }}
          onTouchStart={event => cornerTouchStart(event, index)} onTouchEnd={letGo} onDragStart={event => { own(event); letGo(); }}
          onDragMove={event => { own(event); setMoving({ id: item.id, kind: "corner", index, at: pointOf(event) }); }}
          onDragEnd={event => {
            own(event);
            const at = pointOf(event);
            write({ points: moveCorner(item, index, at), bends: bendsAfterCorner(item, index, at) });
          }} />
      ))}
    </Group>
  );
}
