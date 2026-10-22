"use client";

// A player: a disc in the team's colour with the shirt number, the name
// below when the board shows names. The text stays upright when the pitch
// is turned on a tall screen.
import { Circle, Group, Text } from "react-konva";
import { PLAYER_RADIUS } from "../../../lib/tactics/ball.ts";
import type { Board, PlayerObject } from "../../../lib/tactics/model.ts";
import { nodeRef, useStage } from "../stage/stage-context.ts";
import { useObjectDrag } from "../stage/use-object-drag.ts";

export function PlayerNode({ item, board, selected, upright }: { item: PlayerObject; board: Board; selected: boolean; upright: number }) {
  const shared = useStage();
  const drag = useObjectDrag(item);
  const team = board.teams[item.side];
  const fill = item.color ?? team.color;
  const lastName = item.name?.trim().split(/\s+/).slice(-1)[0] ?? null;
  return (
    <Group ref={nodeRef(shared, item.id)} x={item.x} y={item.y} {...drag}>
      {selected && <Circle radius={PLAYER_RADIUS + 0.55} stroke="#facc15" strokeWidth={0.28} dash={[0.5, 0.35]} />}
      <Circle radius={PLAYER_RADIUS} fill={fill} stroke="#ffffff" strokeWidth={0.22}
        shadowColor="#000000" shadowOpacity={0.35} shadowBlur={0.6} shadowOffsetY={0.2} />
      <Group rotation={upright}>
        {item.number !== null && (
          <Text text={String(item.number)} fontSize={item.number > 99 ? 1.15 : 1.55} fontStyle="bold" fill={team.numberColor}
            width={PLAYER_RADIUS * 2} height={PLAYER_RADIUS * 2} offsetX={PLAYER_RADIUS} offsetY={PLAYER_RADIUS}
            align="center" verticalAlign="middle" listening={false} />
        )}
        {board.showNames && lastName && (
          <Text text={lastName} fontSize={1.15} fontStyle="bold" fill="#ffffff" width={14} offsetX={7} y={PLAYER_RADIUS + 0.35}
            align="center" shadowColor="#000000" shadowOpacity={0.8} shadowBlur={0.4} listening={false} />
        )}
      </Group>
    </Group>
  );
}
