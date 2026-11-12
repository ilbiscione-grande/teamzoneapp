"use client";

// The ball, with a soft glow while a player holds it. In a lofted pass it
// rises off the pitch (lift, in metres): it grows and bends off its way the
// way a pass arrow in the air does (rise), while its shadow stays on the
// ground under it, a little smaller and fainter the higher it goes. Drawn as a football's
// panels (lib/tactics/ball-look.ts).
import { Circle, Group, Line } from "react-konva";
import { BALL_RADIUS } from "../../../lib/tactics/ball.ts";
import { ballPattern } from "../../../lib/tactics/ball-look.ts";
import type { BallObject } from "../../../lib/tactics/model.ts";
import type { Rendered } from "../../../lib/tactics/timeline.ts";
import { Glow, look } from "./look.tsx";
import { nodeRef, useStage } from "../stage/stage-context.ts";
import { useObjectDrag } from "../stage/use-object-drag.ts";

const pattern = ballPattern(BALL_RADIUS);
const ink = "#111827";

export function BallNode({ item, selected }: { item: BallObject & Rendered; selected: boolean }) {
  const shared = useStage();
  const drag = useObjectDrag(item);
  const lift = item.lift ?? 0;
  const rise = item.rise ?? { x: 0, y: 0 };
  return (
    <Group ref={nodeRef(shared, item.id)} x={item.x} y={item.y} {...look(item)} {...drag}>
      {lift > 0 && <Circle radius={BALL_RADIUS * (1.1 - lift / 30)} fill="#000000" opacity={0.5 - lift / 40} listening={false} perfectDrawEnabled={false} />}
      <Group x={rise.x} y={rise.y} scaleX={1 + lift / 12} scaleY={1 + lift / 12}>
        <Glow item={item} radius={BALL_RADIUS * 2.4} />
        {item.attachedTo && <Circle radius={BALL_RADIUS * 1.7} fill="#ffffff" opacity={0.2} listening={false} />}
        {selected && <Circle radius={BALL_RADIUS + 0.45} stroke="#facc15" strokeWidth={0.22} dash={[0.4, 0.3]} />}
        <Circle radius={BALL_RADIUS} fill="#ffffff" stroke="#111827" strokeWidth={0.12} />
        <Group listening={false} clipFunc={context => { context.arc(0, 0, BALL_RADIUS, 0, Math.PI * 2); }}>
          <Line points={pattern.middle} closed fill={ink} perfectDrawEnabled={false} />
          {pattern.edge.map((points, index) => <Line key={index} points={points} closed fill={ink} perfectDrawEnabled={false} />)}
          {pattern.seams.map((points, index) => <Line key={`s${index}`} points={points} stroke={ink} strokeWidth={0.05} perfectDrawEnabled={false} />)}
        </Group>
        <Circle radius={BALL_RADIUS} stroke={ink} strokeWidth={0.12} listening={false} />
      </Group>
    </Group>
  );
}
