"use client";

// Training equipment seen from above: a cone, a pole, a mannequin or a
// small goal. Turned and resized with the selection's handles.
import { Circle, Group, Line, Rect, RegularPolygon } from "react-konva";
import type { EquipmentObject } from "../../../lib/tactics/model.ts";
import type { Rendered } from "../../../lib/tactics/timeline.ts";
import { Glow, look } from "./look.tsx";
import { nodeRef, useStage } from "../stage/stage-context.ts";
import { useObjectDrag } from "../stage/use-object-drag.ts";

function Shape({ item }: { item: EquipmentObject }) {
  switch (item.type) {
    case "cone":
      return <RegularPolygon sides={3} radius={0.85} fill={item.color} stroke="#ffffff" strokeWidth={0.1} />;
    case "pole":
      return (
        <>
          <Circle radius={0.55} fill="rgba(0,0,0,0.25)" />
          <Rect x={-0.2} y={-1.6} width={0.4} height={3.2} cornerRadius={0.2} fill={item.color} stroke="#1f2937" strokeWidth={0.08} />
        </>
      );
    case "mannequin":
      return (
        <>
          <Rect x={-1} y={-0.45} width={2} height={0.9} cornerRadius={0.45} fill={item.color} stroke="#ffffff" strokeWidth={0.1} />
          <Circle radius={0.42} fill={item.color} stroke="#ffffff" strokeWidth={0.1} />
        </>
      );
    case "goal":
      return (
        <>
          <Rect x={-0.8} y={-1.6} width={1.6} height={3.2} fill="rgba(255,255,255,0.18)" />
          {[-0.8, 0, 0.8].map(y => <Line key={y} points={[-0.8, y, 0.8, y]} stroke="rgba(255,255,255,0.45)" strokeWidth={0.05} />)}
          <Line points={[0.8, -1.6, -0.8, -1.6, -0.8, 1.6, 0.8, 1.6]} stroke={item.color} strokeWidth={0.22} lineCap="round" />
        </>
      );
  }
}

export function EquipmentNode({ item }: { item: EquipmentObject & Rendered }) {
  const shared = useStage();
  const drag = useObjectDrag(item);
  return (
    <Group ref={nodeRef(shared, item.id)} x={item.x} y={item.y} rotation={item.rotation} {...look(item, item.scale)} {...drag}>
      <Glow item={item} radius={2.2} />
      <Shape item={item} />
    </Group>
  );
}
