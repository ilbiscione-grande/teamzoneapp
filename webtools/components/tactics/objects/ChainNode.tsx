"use client";

// A line through players (ChainObject): drawn from where they stand, so it
// follows them through the frames and while one is dragged. Closed, it rings
// the space between them, filled if wished. Picked like any object; it is
// never dragged itself, its players are. With measuring on it shows its
// length, or a closed one the ground inside.
import { useEffect, useState } from "react";
import { Group, Line } from "react-konva";
import { chainPoints, halfway, metres, pathLength, polygonArea, squareMetres } from "../../../lib/tactics/measure.ts";
import type { ChainObject, Point } from "../../../lib/tactics/model.ts";
import type { Rendered } from "../../../lib/tactics/timeline.ts";
import { nodeRef, objectDrag, objectDrop, useStage } from "../stage/stage-context.ts";
import { useObjectDrag } from "../stage/use-object-drag.ts";
import { MeasureTag } from "./MeasureTag.tsx";

const alpha = (hex: string, opacity: number) => {
  const value = hex.replace("#", "");
  const [r, g, b] = [0, 2, 4].map(i => parseInt(value.slice(i, i + 2), 16));
  return `rgba(${r},${g},${b},${opacity})`;
};

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
  return (
    <Group ref={nodeRef(shared, item.id)} opacity={item.opacity ?? 1} {...pick}>
      {selected && <Line points={flat} closed={closed} stroke="#facc15" strokeWidth={item.width + 0.5} opacity={0.5} lineJoin="round" listening={false} />}
      <Line points={flat} closed={closed} stroke={item.color} strokeWidth={item.width} lineJoin="round" lineCap="round"
        dash={item.dashed ? [1, 0.7] : undefined} fill={closed ? alpha(item.color, item.fill * 0.6) : undefined}
        hitStrokeWidth={Math.max(1.6, item.width * 4)} />
      {measure && (
        <MeasureTag at={closed ? middle : halfway(points)} upright={upright}
          text={closed ? squareMetres(polygonArea(points)) : metres(pathLength(points, false))} />
      )}
    </Group>
  );
}
