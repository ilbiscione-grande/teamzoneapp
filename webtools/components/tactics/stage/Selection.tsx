"use client";

// Handles for the selection: a transformer to turn and resize equipment,
// areas and text, and for a single line its two ends and a middle point that
// bends it. Handles are sized for a finger whatever the zoom.
import type Konva from "konva";
import { useEffect, useRef, useState } from "react";
import { Circle, Group, Transformer } from "react-konva";
import type { LineObject, Point, TacticsObject } from "../../../lib/tactics/model.ts";
import { linePoints } from "../objects/LineNode.tsx";
import { useEditor } from "../store.ts";
import { useStage } from "./stage-context.ts";

const TRANSFORMABLE = new Set(["cone", "pole", "mannequin", "goal", "rect", "ellipse", "text"]);

function Transform({ items }: { items: TacticsObject[] }) {
  const shared = useStage();
  const ref = useRef<Konva.Transformer>(null);
  const ids = items.map(item => item.id).join(",");
  useEffect(() => {
    const nodes = items.map(item => shared.nodes.get(item.id)).filter((node): node is Konva.Node => !!node);
    ref.current?.nodes(nodes);
    ref.current?.getLayer()?.batchDraw();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ids, shared]);
  const single = items.length === 1 ? items[0] : null;
  const resizable = single !== null && (single.type === "rect" || single.type === "ellipse");
  return (
    <Transformer ref={ref} rotateEnabled flipEnabled={false} keepRatio={!resizable}
      enabledAnchors={resizable ? ["top-left", "top-right", "bottom-left", "bottom-right", "middle-left", "middle-right", "top-center", "bottom-center"] : ["top-left", "top-right", "bottom-left", "bottom-right"]}
      anchorSize={22} anchorCornerRadius={11} borderStroke="#facc15" anchorStroke="#facc15" rotationSnaps={[0, 45, 90, 135, 180, 225, 270, 315]}
      ignoreStroke
      onTransformEnd={() => {
        const patches: Record<string, Partial<TacticsObject>> = {};
        for (const item of items) {
          const node = shared.nodes.get(item.id);
          if (!node) continue;
          const sx = node.scaleX(), sy = node.scaleY();
          const common = { x: node.x(), y: node.y(), rotation: node.rotation() };
          if (item.type === "rect" || item.type === "ellipse") {
            patches[item.id] = { ...common, width: Math.max(0.5, item.width * sx), height: Math.max(0.5, item.height * sy) };
            node.scale({ x: 1, y: 1 });
          } else if (item.type === "text") {
            patches[item.id] = { ...common, size: Math.min(12, Math.max(0.8, item.size * sy)) };
            node.scale({ x: 1, y: 1 });
          } else if ("scale" in item) {
            patches[item.id] = { ...common, scale: Math.min(4, Math.max(0.3, sx)) };
          }
        }
        useEditor.getState().patch(patches);
      }} />
  );
}

function LineHandles({ item }: { item: LineObject }) {
  const shared = useStage();
  const radius = shared.metresPerPixel() * 13;
  const [x1, y1, x2, y2] = item.points;
  const [draft, setDraft] = useState<{ start: Point; end: Point; control: Point | null } | null>(null);
  const shape = draft ?? { start: { x: x1, y: y1 }, end: { x: x2, y: y2 }, control: item.control };
  const middle = shape.control ?? { x: (shape.start.x + shape.end.x) / 2, y: (shape.start.y + shape.end.y) / 2 };

  // While a handle moves, the line's own shape is redrawn directly.
  const redraw = (next: { start: Point; end: Point; control: Point | null }) => {
    setDraft(next);
    // The line and its selection halo both follow.
    const points = linePoints({ ...item, points: [next.start.x, next.start.y, next.end.x, next.end.y], control: next.control });
    (shared.nodes.get(item.id) as Konva.Group | undefined)?.getChildren().forEach(child => (child as Konva.Line).points(points));
  };
  const commit = (next: { start: Point; end: Point; control: Point | null }) => {
    setDraft(null);
    useEditor.getState().patch({ [item.id]: { points: [next.start.x, next.start.y, next.end.x, next.end.y], control: next.control } });
  };
  const handle = (key: string, at: Point, move: (p: Point) => { start: Point; end: Point; control: Point | null }, fill: string) => (
    <Circle key={key} x={at.x} y={at.y} radius={radius} fill={fill} stroke="#111827" strokeWidth={radius * 0.18} draggable
      onMouseDown={event => { event.cancelBubble = true; }} onTouchStart={event => { event.cancelBubble = true; }}
      onDragMove={event => redraw(move({ x: event.target.x(), y: event.target.y() }))}
      onDragEnd={event => commit(move({ x: event.target.x(), y: event.target.y() }))}
      onDblClick={() => key === "mid" && commit({ ...shape, control: null })}
      onDblTap={() => key === "mid" && commit({ ...shape, control: null })} />
  );
  return (
    <Group x={item.x} y={item.y}>
      {handle("start", shape.start, p => ({ ...shape, start: p }), "#facc15")}
      {handle("end", shape.end, p => ({ ...shape, end: p }), "#facc15")}
      {handle("mid", middle, p => ({ ...shape, control: p }), shape.control ? "#ffffff" : "rgba(255,255,255,0.6)")}
    </Group>
  );
}

export function Selection({ objects, selection }: { objects: TacticsObject[]; selection: string[] }) {
  const selected = objects.filter(item => selection.includes(item.id) && !item.locked && !item.hidden);
  const transformable = selected.filter(item => TRANSFORMABLE.has(item.type));
  const line = selected.length === 1 && selected[0].type === "line" ? selected[0] : null;
  return (
    <>
      {transformable.length > 0 && <Transform items={transformable} />}
      {line && <LineHandles key={line.id + line.points.join(",")} item={line} />}
    </>
  );
}
