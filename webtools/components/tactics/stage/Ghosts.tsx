"use client";

// Editing a later frame: where the moved objects stood in the frame before,
// as faint ghosts, and the path each takes. A selected object's path has a
// handle in the middle that bends it; a double tap straightens it.
import { Circle, Group, Line } from "react-konva";
import { PLAYER_RADIUS } from "../../../lib/tactics/ball.ts";
import type { Point, TacticsObject } from "../../../lib/tactics/model.ts";
import { controlThrough, curveMiddle } from "../../../lib/tactics/path.ts";
import { curvePoint } from "../../../lib/tactics/timeline.ts";
import { useEditor } from "../store.ts";
import { useStage } from "./stage-context.ts";

const MOVING = new Set(["player", "ball", "cone", "pole", "mannequin", "goal"]);

function pathPoints(from: Point, to: Point, control: Point | null | undefined): number[] {
  const points: number[] = [];
  for (let i = 0; i <= 20; i++) {
    const at = curvePoint(from, to, control, i / 20);
    points.push(at.x, at.y);
  }
  return points;
}

export function Ghosts({ previous, current, selection, editable }: { previous: TacticsObject[]; current: TacticsObject[]; selection: string[]; editable: boolean }) {
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
        return (
          <Group key={item.id}>
            <Line points={pathPoints(from, to, item.pathControl)} stroke="#ffffff" strokeWidth={0.18} dash={[0.6, 0.5]} opacity={0.75} listening={false} perfectDrawEnabled={false} />
            <Circle x={from.x} y={from.y} radius={item.type === "player" ? PLAYER_RADIUS : 0.9} fill="#ffffff" opacity={0.22}
              stroke="#ffffff" strokeWidth={0.12} dash={[0.4, 0.3]} listening={false} perfectDrawEnabled={false} />
            {selected && editable && (
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
