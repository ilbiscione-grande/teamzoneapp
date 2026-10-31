"use client";

// Handles for the selection: a transformer to turn and resize equipment
// and text with one corner handle (a lone area is turned by it and sized by a
// handle of its own, drawn at its true size as it goes) (equipment grows around its middle,
// so the object itself stays easy to see), and for a single line its two ends and a middle point that
// bends it; for a single player, when the board shows facing, a handle that
// turns them. Handles are sized for a finger whatever the zoom.
import type Konva from "konva";
import { useEffect, useRef, useState } from "react";
import { Circle, Group, Transformer } from "react-konva";
import type { LineObject, Point, ShapeObject, TacticsObject } from "../../../lib/tactics/model.ts";
import { useEditor } from "../store.ts";
import { FacingHandle } from "./FacingHandle.tsx";
import { useStage } from "./stage-context.ts";

const TRANSFORMABLE = new Set(["cone", "pole", "mannequin", "goal", "rect", "ellipse", "text"]);

function Transform({ items, upright }: { items: TacticsObject[]; upright: number }) {
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
  const resizable = single !== null && (single.type === "rect" || single.type === "ellipse" || single.type === "text");
  const area = single !== null && (single.type === "rect" || single.type === "ellipse");
  // The box follows an area sized by its handle.
  const reshaping = useEditor(state => state.reshaping);
  useEffect(() => { ref.current?.forceUpdate(); }, [reshaping, items]);
  return (
    <Transformer ref={ref} rotateEnabled flipEnabled={false} keepRatio={!resizable}
      enabledAnchors={area ? [] : ["bottom-right"]} centeredScaling={!resizable} padding={10}
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
            // The box changes; the letters keep their size.
            const text = (node as Konva.Group).findOne("Text");
            const width = item.width ?? text?.width() ?? 1, height = item.height ?? text?.height() ?? 1;
            // Text is drawn turned upright on a turned pitch; that turn is not its own.
            patches[item.id] = { ...common, rotation: common.rotation - upright, width: Math.max(item.size, width * sx), height: Math.max(item.size, height * sy) };
            node.scale({ x: 1, y: 1 });
          } else if ("scale" in item) {
            patches[item.id] = { ...common, scale: Math.min(4, Math.max(0.3, sx)) };
          } else if (item.type === "player") {
            // A player turns (the way they face) but keeps their size.
            patches[item.id] = common;
            node.scale({ x: 1, y: 1 });
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

  // While a handle moves, the line is drawn as it will be, its head, edge and length too.
  const redraw = (next: { start: Point; end: Point; control: Point | null }) => {
    setDraft(next);
    useEditor.getState().setReshaping({ id: item.id, patch: { points: [next.start.x, next.start.y, next.end.x, next.end.y], control: next.control } });
  };
  const commit = (next: { start: Point; end: Point; control: Point | null }) => {
    setDraft(null);
    useEditor.getState().setReshaping(null);
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

/**
 * A lone area's corner handle: its opposite corner stays put and the area
 * is drawn at its true size as the handle moves, its measure too, as when
 * it is first laid out (not stretched as a transformer would).
 */
function AreaHandle({ item }: { item: ShapeObject }) {
  const shared = useStage();
  const radius = shared.metresPerPixel() * 11;
  const [size, setSize] = useState<{ x: number; y: number; width: number; height: number } | null>(null);
  const shape = size ?? { x: item.x, y: item.y, width: item.width, height: item.height };
  const turn = (item.rotation * Math.PI) / 180;
  const [cos, sin] = [Math.cos(turn), Math.sin(turn)];
  const turned = (dx: number, dy: number) => ({ x: dx * cos - dy * sin, y: dx * sin + dy * cos });
  const fixed = { x: shape.x + turned(-shape.width / 2, -shape.height / 2).x, y: shape.y + turned(-shape.width / 2, -shape.height / 2).y };
  const corner = { x: shape.x + turned(shape.width / 2, shape.height / 2).x, y: shape.y + turned(shape.width / 2, shape.height / 2).y };
  const sized = (at: Point) => {
    const [dx, dy] = [at.x - fixed.x, at.y - fixed.y];
    const width = Math.max(0.5, dx * cos + dy * sin), height = Math.max(0.5, -dx * sin + dy * cos);
    const middle = turned(width / 2, height / 2);
    return { x: fixed.x + middle.x, y: fixed.y + middle.y, width, height };
  };
  return (
    <Circle x={corner.x} y={corner.y} radius={radius} fill="#facc15" stroke="#111827" strokeWidth={radius * 0.18} draggable
      onMouseDown={event => { event.cancelBubble = true; }} onTouchStart={event => { event.cancelBubble = true; }}
      onDragMove={event => {
        const next = sized({ x: event.target.x(), y: event.target.y() });
        setSize(next);
        useEditor.getState().setReshaping({ id: item.id, patch: next });
      }}
      onDragEnd={event => {
        const next = sized({ x: event.target.x(), y: event.target.y() });
        setSize(null);
        useEditor.getState().setReshaping(null);
        useEditor.getState().patch({ [item.id]: next });
      }} />
  );
}

/** facing: the board shows which way players face, so a single selected player gets a handle to turn them. */
export function Selection({ objects, selection, upright, facing = false }: { objects: TacticsObject[]; selection: string[]; upright: number; facing?: boolean }) {
  const selected = objects.filter(item => selection.includes(item.id) && !item.locked && !item.hidden);
  const transformable = selected.filter(item => TRANSFORMABLE.has(item.type));
  const line = selected.length === 1 && selected[0].type === "line" ? selected[0] : null;
  const area = selected.length === 1 && (selected[0].type === "rect" || selected[0].type === "ellipse") ? selected[0] : null;
  const player = facing && selected.length === 1 && selected[0].type === "player" ? selected[0] : null;
  return (
    <>
      {transformable.length > 0 && <Transform items={transformable} upright={upright} />}
      {area && <AreaHandle key={area.id + area.width + area.height + area.x + area.y + area.rotation} item={area} />}
      {line && <LineHandles key={line.id + line.points.join(",")} item={line} />}
      {player && <FacingHandle key={player.id} item={player} />}
    </>
  );
}
