"use client";

// The ball, with a soft glow while a player holds it. In a lofted pass it
// rises off the pitch (lift, in metres): it grows and moves up on the
// screen while its shadow stays on the ground.
import { Circle, Group, RegularPolygon } from "react-konva";
import { BALL_RADIUS } from "../../../lib/tactics/ball.ts";
import type { BallObject } from "../../../lib/tactics/model.ts";
import type { Rendered } from "../../../lib/tactics/timeline.ts";
import { Glow, look } from "./look.tsx";
import { nodeRef, useStage } from "../stage/stage-context.ts";
import { useObjectDrag } from "../stage/use-object-drag.ts";

export function BallNode({ item, selected, upright }: { item: BallObject & Rendered; selected: boolean; upright: number }) {
  const shared = useStage();
  const drag = useObjectDrag(item);
  const lift = item.lift ?? 0;
  return (
    <Group ref={nodeRef(shared, item.id)} x={item.x} y={item.y} {...look(item)} {...drag}>
      {lift > 0 && <Circle radius={BALL_RADIUS * (1 - lift / 20)} fill="rgba(0,0,0,0.35)" listening={false} perfectDrawEnabled={false} />}
      {/* Up on the screen whichever way the pitch is turned. */}
      <Group rotation={upright}>
        <Group y={-lift * 0.45} scaleX={1 + lift / 12} scaleY={1 + lift / 12}>
          <Group rotation={-upright}>
            <Glow item={item} radius={BALL_RADIUS * 2.4} />
            {item.attachedTo && <Circle radius={BALL_RADIUS * 1.7} fill="#ffffff" opacity={0.2} listening={false} />}
            {selected && <Circle radius={BALL_RADIUS + 0.45} stroke="#facc15" strokeWidth={0.22} dash={[0.4, 0.3]} />}
            <Circle radius={BALL_RADIUS} fill="#ffffff" stroke="#111827" strokeWidth={0.12} />
            <RegularPolygon sides={5} radius={BALL_RADIUS * 0.42} fill="#111827" listening={false} />
          </Group>
        </Group>
      </Group>
    </Group>
  );
}
