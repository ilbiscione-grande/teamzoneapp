"use client";

// The board: the pitch fitted to its frame (turned on a tall screen), with
// pan and zoom by dragging the grass, pinching, the mouse wheel or the
// buttons. The pitch has a layer of its own that never redraws while an
// object moves; zoom and pan move the Konva groups directly while fingers
// move and are kept when they lift, so the board never waits for React.
import Konva from "konva";
import { useEffect, useMemo, useRef, useState } from "react";
import { Group, Layer, Stage } from "react-konva";
import { distance, fitView, midpoint, viewRect, zoomAround, type Viewport } from "../../../lib/tactics/geometry.ts";
import type { Point } from "../../../lib/tactics/model.ts";
import { ObjectNode } from "../objects/ObjectNode.tsx";
import { activeBoard, activeObjects, useEditor } from "../store.ts";
import { DraftNode } from "./DraftNode.tsx";
import { Pitch } from "./Pitch.tsx";
import { Selection } from "./Selection.tsx";
import { StageContext, type StageShared } from "./stage-context.ts";
import { isDrawTool, isPlaceTool, useDrawing } from "./use-drawing.ts";

// A drag moves one node; Konva need not rebuild its hit map on every step.
// Pinching is read from the browser's own touch events instead.
Konva.hitOnDragEnabled = false;
// Sharper than 2× costs more than it shows on a tablet.
if (typeof window !== "undefined") Konva.pixelRatio = Math.min(window.devicePixelRatio || 1, 2);

const IDENTITY: Viewport = { x: 0, y: 0, scale: 1 };

export default function BoardStage({ editable = true }: { editable?: boolean }) {
  const frame = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState({ width: 0, height: 0 });
  const board = useEditor(activeBoard);
  const objects = useEditor(activeObjects);
  const selection = useEditor(state => state.selection);
  const tool = useEditor(state => state.tool);
  // The same zoom and pan on both layers: the pitch's group is dragged, the
  // objects' group follows.
  const pitchView = useRef<Konva.Group>(null);
  const objectView = useRef<Konva.Group>(null);
  const content = useRef<Konva.Group>(null);
  const [viewport, setViewport] = useState<Viewport>(IDENTITY);
  const live = useRef<Viewport>(IDENTITY);
  const pinch = useRef<{ distance: number; center: Point } | null>(null);
  const nodes = useRef(new Map<string, Konva.Node>());

  useEffect(() => {
    const element = frame.current;
    if (!element) return;
    const observer = new ResizeObserver(([entry]) => setSize({ width: entry.contentRect.width, height: entry.contentRect.height }));
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  const fit = useMemo(() => fitView(viewRect(board?.view ?? "full"), size.width, size.height), [board?.view, size.width, size.height]);
  // A new board, view or frame size starts from the whole view.
  useEffect(() => {
    live.current = IDENTITY;
    setViewport(IDENTITY);
  }, [board?.id, board?.view, size.width, size.height]);

  const shared = useMemo<StageShared>(() => ({
    nodes: nodes.current,
    content,
    metresPerPixel: () => 1 / (fit.scale * live.current.scale || 1),
    editable,
  }), [fit.scale, editable]);

  const pointer = () => content.current?.getRelativePointerPosition() ?? null;
  const drawing = useDrawing(pointer);

  const applyViewport = (next: Viewport, commit: boolean) => {
    live.current = next;
    for (const group of [pitchView.current, objectView.current]) {
      group?.setAttrs({ x: next.x, y: next.y, scaleX: next.scale, scaleY: next.scale });
      group?.getLayer()?.batchDraw();
    }
    if (commit) setViewport(next);
  };
  const applyRef = useRef(applyViewport);
  applyRef.current = applyViewport;

  // Two fingers zoom and move the board, whatever was being dragged.
  useEffect(() => {
    const element = frame.current;
    if (!element) return;
    const points = (event: TouchEvent): [Point, Point] | null => {
      if (event.touches.length < 2) return null;
      const rect = element.getBoundingClientRect();
      const at = (touch: Touch) => ({ x: touch.clientX - rect.left, y: touch.clientY - rect.top });
      return [at(event.touches[0]), at(event.touches[1])];
    };
    const onMove = (event: TouchEvent) => {
      const pair = points(event);
      if (!pair) return;
      event.preventDefault();
      if (pitchView.current?.isDragging()) pitchView.current.stopDrag();
      nodes.current.forEach(node => { if (node.isDragging()) node.stopDrag(); });
      const gap = distance(pair[0], pair[1]);
      const center = midpoint(pair[0], pair[1]);
      if (pinch.current) {
        const zoomed = zoomAround(live.current, gap / pinch.current.distance, center);
        applyRef.current({ ...zoomed, x: zoomed.x + center.x - pinch.current.center.x, y: zoomed.y + center.y - pinch.current.center.y }, false);
      }
      pinch.current = { distance: gap, center };
    };
    const onEnd = (event: TouchEvent) => {
      if (!pinch.current || event.touches.length >= 2) return;
      pinch.current = null;
      setViewport(live.current);
    };
    element.addEventListener("touchmove", onMove, { passive: false });
    element.addEventListener("touchend", onEnd);
    element.addEventListener("touchcancel", onEnd);
    return () => {
      element.removeEventListener("touchmove", onMove);
      element.removeEventListener("touchend", onEnd);
      element.removeEventListener("touchcancel", onEnd);
    };
  }, [size.width > 0]); // eslint-disable-line react-hooks/exhaustive-deps

  const zoomBy = (factor: number) => applyViewport(zoomAround(live.current, factor, { x: size.width / 2, y: size.height / 2 }), true);

  if (!board) return <div ref={frame} className="tb-stage" />;
  const upright = -fit.rotation;
  const pannable = tool === "select" || isPlaceTool(tool);
  // Hidden objects stay in the list, not on the pitch.
  const visible = objects.filter(item => !item.hidden);
  const fitted = { x: fit.x, y: fit.y, scaleX: fit.scale, scaleY: fit.scale, rotation: fit.rotation };
  const zoomed = { x: viewport.x, y: viewport.y, scaleX: viewport.scale, scaleY: viewport.scale };

  return (
    <div ref={frame} className="tb-stage" data-tool={tool}>
      {size.width > 0 && (
        <StageContext.Provider value={shared}>
          <Stage width={size.width} height={size.height}
            onWheel={event => {
              event.evt.preventDefault();
              const at = event.target.getStage()?.getPointerPosition();
              if (at) applyViewport(zoomAround(live.current, event.evt.deltaY > 0 ? 1 / 1.12 : 1.12, at), true);
            }}
            onPointerDown={() => { if (!pinch.current && editable && isDrawTool(tool)) drawing.start(); }}
            onPointerMove={() => drawing.move()}
            onPointerUp={() => drawing.end()}
            onClick={event => {
              if (event.evt.button !== 0 || !editable) return;
              if (isPlaceTool(tool)) drawing.place();
              else if (tool === "select" && event.target.name() === "grass") useEditor.getState().select([]);
            }}
            onTap={event => {
              if (!editable || pinch.current) return;
              if (isPlaceTool(tool)) drawing.place();
              else if (tool === "select" && event.target.name() === "grass") useEditor.getState().select([]);
            }}>
            <Layer>
              <Group ref={pitchView} {...zoomed} draggable={pannable}
                onDragMove={event => {
                  live.current = { ...live.current, x: event.target.x(), y: event.target.y() };
                  objectView.current?.position({ x: live.current.x, y: live.current.y });
                }}
                onDragEnd={() => setViewport(live.current)}>
                <Group {...fitted}>
                  <Pitch view={board.view} overlay={board.overlay} />
                </Group>
              </Group>
            </Layer>
            <Layer>
              <Group ref={objectView} {...zoomed}>
                <Group ref={content} {...fitted}>
                  {visible.map(item => (
                    <ObjectNode key={item.id} item={item} board={board} selected={selection.includes(item.id)} upright={upright} />
                  ))}
                  {editable && <Selection objects={objects} selection={selection} />}
                  {drawing.draft && <DraftNode draft={drawing.draft} />}
                </Group>
              </Group>
            </Layer>
          </Stage>
        </StageContext.Provider>
      )}
      <div className="tb-zoom" role="group" aria-label="Zoom">
        <button type="button" onClick={() => zoomBy(1.25)} aria-label="Zooma in">+</button>
        <button type="button" onClick={() => zoomBy(0.8)} aria-label="Zooma ut">−</button>
        <button type="button" onClick={() => applyViewport(IDENTITY, true)} aria-label="Visa hela" disabled={viewport === IDENTITY}>⤢</button>
      </div>
    </div>
  );
}
