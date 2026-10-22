"use client";

// The ball, with a soft glow while a player holds it.
import { Circle, Group, RegularPolygon } from "react-konva";
import { BALL_RADIUS } from "../../../lib/tactics/ball.ts";
import type { BallObject } from "../../../lib/tactics/model.ts";
import { nodeRef, useStage } from "../stage/stage-context.ts";
import { useObjectDrag } from "../stage/use-object-drag.ts";

export function BallNode({ item, selected }: { item: BallObject; selected: boolean }) {
  const shared = useStage();
  const drag = useObjectDrag(item);
  return (
    <Group ref={nodeRef(shared, item.id)} x={item.x} y={item.y} {...drag}>
      {item.attachedTo && <Circle radius={BALL_RADIUS * 1.7} fill="#ffffff" opacity={0.2} listening={false} />}
      {selected && <Circle radius={BALL_RADIUS + 0.45} stroke="#facc15" strokeWidth={0.22} dash={[0.4, 0.3]} />}
      <Circle radius={BALL_RADIUS} fill="#ffffff" stroke="#111827" strokeWidth={0.12} />
      <RegularPolygon sides={5} radius={BALL_RADIUS * 0.42} fill="#111827" listening={false} />
    </Group>
  );
}
