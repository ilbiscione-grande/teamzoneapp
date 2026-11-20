"use client";

// A player: a disc in the team's colour with one short thing in it and, under
// it, what else the board shows (number, name, position: player-label.ts).
// Holding the ball, the player is lit like the ball. The text stays upright when the pitch
// is turned on a tall screen. With the board's facing on, a cone shows which
// way the player faces: their own turn, or the way they run while playing.
import { Circle, Group, Text, Wedge } from "react-konva";
import { PLAYER_RADIUS } from "../../../lib/tactics/ball.ts";
import type { Board, PlayerObject } from "../../../lib/tactics/model.ts";
import { insideSize, playerLabel } from "../../../lib/tactics/player-label.ts";
import { useLanguage } from "../../language";
import { standingFacing, type Rendered } from "../../../lib/tactics/timeline.ts";
import { Glow, look } from "./look.tsx";
import { nodeRef, useStage } from "../stage/stage-context.ts";
import { useObjectDrag } from "../stage/use-object-drag.ts";

export function PlayerNode({ item, board, selected, upright, holding }: { item: PlayerObject & Rendered; board: Board; selected: boolean; upright: number; holding: boolean }) {
  const shared = useStage();
  const drag = useObjectDrag(item);
  const team = board.teams[item.side];
  const fill = item.color ?? team.color;
  const { inside, below } = playerLabel(item, board, useLanguage().locale);
  // The node turns with the player; the cone is set against that turn.
  const facing = (item.facing ?? standingFacing(item)) - item.rotation;
  return (
    <Group ref={nodeRef(shared, item.id)} x={item.x} y={item.y} rotation={item.rotation} {...look(item)} {...drag}>
      {board.showFacing && (
        <Wedge radius={PLAYER_RADIUS * 3.2} angle={56} rotation={facing - 28} fill={fill} opacity={0.32} listening={false} perfectDrawEnabled={false} />
      )}
      <Glow item={item} radius={PLAYER_RADIUS * 2} />
      {holding && <Circle radius={PLAYER_RADIUS + 0.75} fill="#ffffff" opacity={0.28} listening={false} perfectDrawEnabled={false} />}
      {selected && <Circle radius={PLAYER_RADIUS + 0.55} stroke="#facc15" strokeWidth={0.28} dash={[0.5, 0.35]} />}
      {/* No canvas shadows: they are redrawn for every player on every frame. */}
      <Circle radius={PLAYER_RADIUS + 0.12} fill="rgba(0,0,0,0.28)" y={0.18} listening={false} perfectDrawEnabled={false} />
      <Circle radius={PLAYER_RADIUS} fill={fill} stroke="#ffffff" strokeWidth={0.22} perfectDrawEnabled={false} />
      <Group rotation={upright - item.rotation}>
        {inside && (
          <Text text={inside} fontSize={insideSize(inside)} fontStyle="bold" fill={team.numberColor} wrap="none"
            width={PLAYER_RADIUS * 2} height={PLAYER_RADIUS * 2} offsetX={PLAYER_RADIUS} offsetY={PLAYER_RADIUS}
            align="center" verticalAlign="middle" listening={false} />
        )}
        {below && (
          <Text text={below} fontSize={1.15} fontStyle="bold" fill="#ffffff" width={14} offsetX={7} y={PLAYER_RADIUS + 0.35}
            align="center" stroke="rgba(11,17,28,0.9)" strokeWidth={0.14} fillAfterStrokeEnabled listening={false} perfectDrawEnabled={false} />
        )}
      </Group>
    </Group>
  );
}
