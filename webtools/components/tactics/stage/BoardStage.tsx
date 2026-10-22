"use client";

// The board: the pitch fitted to its frame (turned on a tall screen), with
// pan and zoom by dragging the grass, pinching, the mouse wheel or the
// buttons. Zoom and pan move the Konva group directly while fingers move and
// are kept when they lift, so the board never waits for React.
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

// Pinching while something is dragged must still reach the stage.
Konva.hitOnDragEnabled = true;

const IDENTITY: Viewport = { x: 0, y: 0, scale: 1 };

export default function BoardStage({ editable = true }: { editable?: boolean }) {
  const frame = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState({ width: 0, height: 0 });
  const board = useEditor(activeBoard);
  const objects = useEditor(activeObjects);
  const selection = useEditor(state => state.selection);
  const tool = useEditor(state => state.tool);
  const viewportGroup = useRef<Konva.Group>(null);
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
    viewportGroup.current?.setAttrs({ x: next.x, y: next.y, scaleX: next.scale, scaleY: next.scale });
    viewportGroup.current?.getLayer()?.batchDraw();
    if (commit) setViewport(next);
  };

  const zoomBy = (factor: number) => applyViewport(zoomAround(live.current, factor, { x: size.width / 2, y: size.height / 2 }), true);

  const touchPoints = (event: TouchEvent): [Point, Point] | null => {
    const rect = frame.current?.getBoundingClientRect();
    if (!rect || event.touches.length < 2) return null;
    const at = (touch: Touch) => ({ x: touch.clientX - rect.left, y: touch.clientY - rect.top });
    return [at(event.touches[0]), at(event.touches[1])];
  };

  if (!board) return <div ref={frame} className="tb-stage" />;
  const upright = -fit.rotation;
  const pannable = tool === "select" || isPlaceTool(tool);
  // Hidden objects stay in the list, not on the pitch.
  const visible = objects.filter(item => !item.hidden);

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
            onTouchMove={event => {
              const points = touchPoints(event.evt);
              if (!points) return;
              event.evt.preventDefault();
              // Two fingers zoom and move the board, whatever was being dragged.
              if (viewportGroup.current?.isDragging()) viewportGroup.current.stopDrag();
              nodes.current.forEach(node => { if (node.isDragging()) node.stopDrag(); });
              const gap = distance(points[0], points[1]);
              const center = midpoint(points[0], points[1]);
              if (pinch.current) {
                const zoomed = zoomAround(live.current, gap / pinch.current.distance, center);
                applyViewport({ ...zoomed, x: zoomed.x + center.x - pinch.current.center.x, y: zoomed.y + center.y - pinch.current.center.y }, false);
              }
              pinch.current = { distance: gap, center };
            }}
            onTouchEnd={() => {
              if (!pinch.current) return;
              pinch.current = null;
              setViewport(live.current);
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
              <Group ref={viewportGroup} x={viewport.x} y={viewport.y} scaleX={viewport.scale} scaleY={viewport.scale}
                draggable={pannable}
                onDragMove={event => { if (event.target === viewportGroup.current) live.current = { ...live.current, x: event.target.x(), y: event.target.y() }; }}
                onDragEnd={event => { if (event.target === viewportGroup.current) setViewport({ ...live.current, x: event.target.x(), y: event.target.y() }); }}>
                <Group ref={content} x={fit.x} y={fit.y} scaleX={fit.scale} scaleY={fit.scale} rotation={fit.rotation}>
                  <Pitch view={board.view} overlay={board.overlay} />
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
