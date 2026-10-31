"use client";

// A line through players (ChainObject): drawn from where they stand, so it
// follows them through the frames and while one is dragged. Closed, it rings
// the space between them, filled or striped if wished; a ring marks each player's feet. Picked like any object; it is
// never dragged itself, its players are. With measuring on it shows its
// length, or a closed one the ground inside.
import { useEffect, useState } from "react";
import type { Context } from "konva/lib/Context";
import { Circle, Group, Line } from "react-konva";
import { PLAYER_RADIUS } from "../../../lib/tactics/ball.ts";
import { edgeFor } from "../../../lib/tactics/ribbon.ts";
import { AreaFill, alpha } from "./AreaFill.tsx";
import { chainPoints, halfway, metres, pathLength, polygonArea, squareMetres } from "../../../lib/tactics/measure.ts";
import type { ChainObject, Point } from "../../../lib/tactics/model.ts";
import type { Rendered } from "../../../lib/tactics/timeline.ts";
import { nodeRef, objectDrag, objectDrop, useStage } from "../stage/stage-context.ts";
import { useObjectDrag } from "../stage/use-object-drag.ts";
import { MeasureTag } from "./MeasureTag.tsx";

const RING = PLAYER_RADIUS + 0.75;

type Props = { item: ChainObject & Rendered; objects: Rendered[]; selected: boolean; upright: number; measure: boolean };

export function ChainNode({ item, objects, selected, upright, measure }: Props) {
  const shared = useStage();
  const { draggable: _ignored, onDragStart: _start, onDragMove: _move, onDragEnd: _end, ...pick } = useObjectDrag(item);
  // Where dragged players are right now, before the drop is written.
  const [moved, setMoved] = useState<Record<string, Point>>({});
  useEffect(() => {
    const drag = (moves: Record<string, Point>) => {
      if (item.players.some(id => id in moves)) setMoved(moves);
    };
    const drop = () => setMoved({});
    objectDrag.add(drag);
    objectDrop.add(drop);
    return () => { objectDrag.delete(drag); objectDrop.delete(drop); };
  }, [item.players]);

  const points = chainPoints(item, objects, moved);
  if (points.length < 2) return null;
  const closed = item.closed && points.length > 2;
  const flat = points.flatMap(point => [point.x, point.y]);
  const middle = { x: points.reduce((sum, point) => sum + point.x, 0) / points.length, y: points.reduce((sum, point) => sum + point.y, 0) / points.length };
  const xs = points.map(point => point.x), ys = points.map(point => point.y);
  const box = { x: Math.min(...xs), y: Math.min(...ys), width: Math.max(...xs) - Math.min(...xs), height: Math.max(...ys) - Math.min(...ys) };
  const outline = (context: Context) => {
    context.beginPath();
    points.forEach((point, index) => (index === 0 ? context.moveTo(point.x, point.y) : context.lineTo(point.x, point.y)));
    context.closePath();
  };
  const line = { points: flat, closed, lineJoin: "round" as const, lineCap: "round" as const, perfectDrawEnabled: false };
  const dash = item.dashed ? [1, 0.7] : undefined;
  return (
    <Group ref={nodeRef(shared, item.id)} opacity={item.opacity ?? 1} {...pick}>
      {closed && <AreaFill box={box} outline={outline} color={item.color} fill={item.fill} pattern={item.pattern} />}
      {selected && <Line {...line} stroke="#facc15" strokeWidth={item.width + 0.7} opacity={0.5} listening={false} />}
      <Line {...line} dash={dash} stroke={edgeFor(item.color)} strokeWidth={item.width + 0.18} listening={false} />
      <Line {...line} dash={dash} stroke={item.color} strokeWidth={item.width} fill={closed ? "rgba(0,0,0,0)" : undefined}
        fillEnabled={false} hitStrokeWidth={Math.max(1.6, item.width * 4)} />
      {item.rings !== false && points.map((point, index) => (
        // A ring at each player's feet, under the player, as television marks those it joins.
        <Group key={index} x={point.x} y={point.y} listening={false}>
          <Circle radius={RING} fill={alpha(item.color, 0.22)} stroke={edgeFor(item.color)} strokeWidth={0.5} perfectDrawEnabled={false} />
          <Circle radius={RING} stroke={item.color} strokeWidth={0.3} perfectDrawEnabled={false} />
        </Group>
      ))}
      {measure && (
        <MeasureTag at={closed ? middle : halfway(points)} upright={upright}
          text={closed ? squareMetres(polygonArea(points)) : metres(pathLength(points, false))} />
      )}
    </Group>
  );
}
