"use client";

// Editing a later frame: where the moved objects stood in the frame before,
// as faint ghosts, and the path each takes. A selected object's path has a
// handle in the middle that bends it; a double tap straightens it. A ball
// passed in the air also shows its arc over the path, its shadow. The paths
// lie under the objects, the handles over everything, so a player, a line or
// the selection over the middle of a path never takes the drag.
import { Circle, Group, Line } from "react-konva";
import { PLAYER_RADIUS } from "../../../lib/tactics/ball.ts";
import type { Point, TacticsObject } from "../../../lib/tactics/model.ts";
import { airSide, controlThrough, curveMiddle } from "../../../lib/tactics/path.ts";
import { curvePoint, PEAK, RISE } from "../../../lib/tactics/timeline.ts";
import { useEditor } from "../store.ts";
import { useStage } from "./stage-context.ts";

const MOVING = new Set(["player", "ball", "cone", "pole", "mannequin", "goal"]);

/** peak: a ball in the air's top height, the path drawn as its arc, the way it rises off its shadow while playing. */
function pathPoints(from: Point, to: Point, control: Point | null | undefined, peak = 0): number[] {
  const side = peak > 0 ? airSide(from, to) : null;
  const points: number[] = [];
  for (let i = 0; i <= 20; i++) {
    const t = i / 20;
    const at = curvePoint(from, to, control, t);
    const rise = side ? peak * 4 * t * (1 - t) * RISE : 0;
    points.push(at.x + (side?.x ?? 0) * rise, at.y + (side?.y ?? 0) * rise);
  }
  return points;
}

/** ink: what white shows as on the board's pitch. part: the paths and ghosts, or the handles. */
export function Ghosts({ previous, current, selection, editable, ink = "#ffffff", part = "paths" }: {
  previous: TacticsObject[]; current: TacticsObject[]; selection: string[]; editable: boolean; ink?: string; part?: "paths" | "handles";
}) {
  const shared = useStage();
  const before = new Map(previous.map(item => [item.id, item]));
  const handle = shared.metresPerPixel() * 11;
  const moves = current.flatMap(item => {
    const prev = before.get(item.id);
    if (!prev || !MOVING.has(item.type) || item.hidden) return [];
    // A ball held by the same player rides along; it has no path of its own.
    if (item.type === "ball" && prev.type === "ball" && item.attachedTo && item.attachedTo === prev.attachedTo) return [];
    if (Math.hypot(item.x - prev.x, item.y - prev.y) < 0.3) return [];
    return [{ item, prev }];
  });
  return (
    <Group>
      {moves.map(({ item, prev }) => {
        const from = { x: prev.x, y: prev.y };
        const to = { x: item.x, y: item.y };
        const middle = curveMiddle(from, to, item.pathControl);
        const selected = selection.includes(item.id);
        const peak = item.type === "ball" ? PEAK[item.flight ?? "ground"] ?? 0 : 0;
        return (
          <Group key={item.id}>
            {part === "paths" && <>
              <Line points={pathPoints(from, to, item.pathControl)} stroke={ink} strokeWidth={0.18} dash={[0.6, 0.5]} opacity={peak > 0 ? 0.4 : 0.75} listening={false} perfectDrawEnabled={false} />
              {peak > 0 && <Line points={pathPoints(from, to, item.pathControl, peak)} stroke={ink} strokeWidth={0.2} opacity={0.8} listening={false} perfectDrawEnabled={false} />}
              <Circle x={from.x} y={from.y} radius={item.type === "player" ? PLAYER_RADIUS : 0.9} fill={ink} opacity={0.22}
                stroke={ink} strokeWidth={0.12} dash={[0.4, 0.3]} listening={false} perfectDrawEnabled={false} />
            </>}
            {part === "handles" && selected && editable && (
              <Circle x={middle.x} y={middle.y} radius={handle} fill={item.pathControl ? "#ffffff" : "rgba(255,255,255,0.65)"}
                stroke="#111827" strokeWidth={handle * 0.18} draggable
                onMouseDown={event => { event.cancelBubble = true; }} onTouchStart={event => { event.cancelBubble = true; }}
                onDragEnd={event => useEditor.getState().patch({ [item.id]: { pathControl: controlThrough(from, to, { x: event.target.x(), y: event.target.y() }) } })}
                onDblClick={() => useEditor.getState().patch({ [item.id]: { pathControl: null } })}
                onDblTap={() => useEditor.getState().patch({ [item.id]: { pathControl: null } })} />
            )}
          </Group>
        );
      })}
    </Group>
  );
}
