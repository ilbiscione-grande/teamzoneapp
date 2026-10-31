"use client";

// What is being drawn, before it becomes an object; with measuring on, its
// size as it grows. The ruler shows its distance all along.
import { Arrow, Ellipse, Line, Rect } from "react-konva";
import { distance, metres, shapeMeasure } from "../../../lib/tactics/measure.ts";
import { wavePoints } from "../../../lib/tactics/path.ts";
import { MeasureTag } from "../objects/MeasureTag.tsx";
import { RulerNode } from "./RulerNode.tsx";
import type { Draft } from "./use-drawing.ts";

/** ink: what white shows as on the board's pitch. */
export function DraftNode({ draft, ink = "#ffffff", measure = false, upright = 0 }: { draft: Draft; ink?: string; measure?: boolean; upright?: number }) {
  const { start, current } = draft;
  if (draft.tool === "ruler") return <RulerNode from={start} to={current} upright={upright} />;
  const common = { stroke: ink, strokeWidth: 0.3, opacity: 0.85, listening: false, lineCap: "round" as const };
  if (draft.tool === "freehand") return <Line {...common} x={start.x} y={start.y} points={draft.path} tension={0.45} />;
  if (draft.tool === "rect" || draft.tool === "ellipse") {
    const x = Math.min(start.x, current.x), y = Math.min(start.y, current.y);
    const width = Math.abs(current.x - start.x), height = Math.abs(current.y - start.y);
    const size = measure && <MeasureTag at={{ x: x + width / 2, y: y + height / 2 }} text={shapeMeasure({ type: draft.tool, width, height })} upright={upright} />;
    return draft.tool === "rect"
      ? <>{<Rect {...common} stroke="#facc15" x={x} y={y} width={width} height={height} fill="rgba(250,204,21,0.2)" />}{size}</>
      : <>{<Ellipse {...common} stroke="#facc15" x={x + width / 2} y={y + height / 2} radiusX={width / 2} radiusY={height / 2} fill="rgba(250,204,21,0.2)" />}{size}</>;
  }
  const points = [start.x, start.y, current.x, current.y];
  const length = measure && <MeasureTag at={{ x: (start.x + current.x) / 2, y: (start.y + current.y) / 2 }} text={metres(distance(start, current))} upright={upright} />;
  if (draft.tool === "line") return <><Line {...common} points={points} />{length}</>;
  if (draft.tool === "dribble") return <><Arrow {...common} points={wavePoints(points)} tension={0.4} fill={ink} pointerLength={1.5} pointerWidth={1.4} />{length}</>;
  return <><Arrow {...common} points={points} fill={ink} pointerLength={1.5} pointerWidth={1.4} dash={draft.tool === "run" ? [1.1, 0.8] : undefined} />{length}</>;
}
