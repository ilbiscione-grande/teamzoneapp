"use client";

// The board: the pitch fitted to its frame (turned on a tall screen), with
// zoom by pinching, the mouse wheel or the buttons. With the whole view in
// sight, dragging over the grass draws a band that selects what it
// touches; zoomed in, dragging the grass moves around the pitch instead. The pitch has a layer of its own that never redraws while an
// object moves; zoom and pan move the Konva groups directly while fingers
// move and are kept when they lift, so the board never waits for React.
import Konva from "konva";
import { useEffect, useMemo, useRef, useState } from "react";
import { Group, Layer, Rect, Stage } from "react-konva";
import { distance, fitView, midpoint, viewRect, zoomAround, type Viewport } from "../../../lib/tactics/geometry.ts";
import type { Point } from "../../../lib/tactics/model.ts";
import { objectsAt } from "../../../lib/tactics/timeline.ts";
import { ObjectNode } from "../objects/ObjectNode.tsx";
import { activeBoard, activeObjects, useEditor } from "../store.ts";
import { DraftNode } from "./DraftNode.tsx";
import { Ghosts } from "./Ghosts.tsx";
import { Pitch } from "./Pitch.tsx";
import { Selection } from "./Selection.tsx";
import { StageContext, stageHolder, type StageShared } from "./stage-context.ts";
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
  const playing = useEditor(state => state.playing);
  const playhead = useEditor(state => state.playhead);
  const frameIndex = useEditor(state => state.frameIndex);
  // Nothing is edited while the board plays.
  const canEdit = editable && !playing;
  // The same zoom and pan on both layers: the pitch's group is dragged, the
  // objects' group follows.
  const pitchView = useRef<Konva.Group>(null);
  const objectView = useRef<Konva.Group>(null);
  const content = useRef<Konva.Group>(null);
  const [viewport, setViewport] = useState<Viewport>(IDENTITY);
  const live = useRef<Viewport>(IDENTITY);
  const pinch = useRef<{ distance: number; center: Point } | null>(null);
  const nodes = useRef(new Map<string, Konva.Node>());
  // The selecting band, in the stage's pixels: drawn directly while it is dragged.
  const band = useRef<Konva.Rect>(null);
  const bandStart = useRef<Point | null>(null);
  const bandMoved = useRef(false);
  const cancelBand = () => {
    bandStart.current = null;
    band.current?.visible(false);
    band.current?.getLayer()?.batchDraw();
  };
  const cancelBandRef = useRef(cancelBand);
  cancelBandRef.current = cancelBand;

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
    editable: canEdit,
  }), [fit.scale, canEdit]);

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
      cancelBandRef.current();
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
  // Zoomed in, the grass moves the view; with the whole view in sight it selects.
  const zoomedIn = viewport.scale > 1.001;
  const pannable = zoomedIn && (tool === "select" || isPlaceTool(tool));
  const bandable = canEdit && tool === "select" && !zoomedIn;
  const stagePointer = (event: Konva.KonvaEventObject<PointerEvent>) => event.target.getStage()?.getPointerPosition() ?? null;
  const endBand = (event: Konva.KonvaEventObject<PointerEvent>) => {
    const start = bandStart.current;
    const end = stagePointer(event);
    cancelBand();
    if (!start || !end || !bandMoved.current) return;
    const area = { x: Math.min(start.x, end.x), y: Math.min(start.y, end.y), width: Math.abs(end.x - start.x), height: Math.abs(end.y - start.y) };
    const touched = visible.filter(item => {
      const node = nodes.current.get(item.id);
      return node && Konva.Util.haveIntersection(area, node.getClientRect());
    }).map(item => item.id);
    const { select, selection: current } = useEditor.getState();
    select(event.evt.shiftKey ? [...new Set([...current, ...touched])] : touched);
  };
  // A band that moved ends in a click on the grass; that click must not clear what it chose.
  const afterBand = () => {
    const moved = bandMoved.current;
    bandMoved.current = false;
    return moved;
  };
  // Hidden objects stay in the list, not on the pitch. Playing shows the moves.
  const shown = playing ? objectsAt(board.frames, playhead) : objects;
  const visible = shown.filter(item => !item.hidden);
  // Ghosts of the frame before are for editing; a shared board shows none.
  const previous = canEdit && frameIndex > 0 ? board.frames[frameIndex - 1]?.objects : undefined;
  const fitted = { x: fit.x, y: fit.y, scaleX: fit.scale, scaleY: fit.scale, rotation: fit.rotation };
  const zoomed = { x: viewport.x, y: viewport.y, scaleX: viewport.scale, scaleY: viewport.scale };

  return (
    <div ref={frame} className="tb-stage" data-tool={tool}>
      {/* Konva fails drawing into a board without width or height (a phone with the panel open). */}
      {size.width > 0 && size.height > 0 && (
        <StageContext.Provider value={shared}>
          <Stage ref={node => { stageHolder.current = node; }} width={size.width} height={size.height}
            onWheel={event => {
              event.evt.preventDefault();
              const at = event.target.getStage()?.getPointerPosition();
              if (at) applyViewport(zoomAround(live.current, event.evt.deltaY > 0 ? 1 / 1.12 : 1.12, at), true);
            }}
            onPointerDown={event => {
              if (pinch.current) return;
              if (canEdit && isDrawTool(tool)) drawing.start();
              else if (bandable && event.target.name() === "grass") {
                bandStart.current = stagePointer(event);
                bandMoved.current = false;
              }
            }}
            onPointerMove={event => {
              drawing.move();
              const start = bandStart.current, at = bandStart.current && stagePointer(event);
              if (!start || !at) return;
              if (!bandMoved.current && Math.hypot(at.x - start.x, at.y - start.y) < 6) return;
              bandMoved.current = true;
              band.current?.setAttrs({ x: Math.min(start.x, at.x), y: Math.min(start.y, at.y), width: Math.abs(at.x - start.x), height: Math.abs(at.y - start.y), visible: true });
              band.current?.getLayer()?.batchDraw();
            }}
            onPointerUp={event => { drawing.end(); endBand(event); }}
            onClick={event => {
              if (afterBand()) return;
              if (event.evt.button !== 0 || !canEdit) return;
              if (isPlaceTool(tool)) drawing.place();
              else if (tool === "select" && event.target.name() === "grass") useEditor.getState().select([]);
            }}
            onTap={event => {
              if (afterBand()) return;
              if (!canEdit || pinch.current) return;
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
                  {previous && <Ghosts previous={previous} current={objects} selection={selection} editable={canEdit} />}
                  {visible.map(item => (
                    <ObjectNode key={item.id} item={item} board={board} selected={selection.includes(item.id)} upright={upright} />
                  ))}
                  {canEdit && <Selection objects={objects} selection={selection} upright={upright} />}
                  {drawing.draft && <DraftNode draft={drawing.draft} />}
                </Group>
              </Group>
            </Layer>
            {canEdit && (
              <Layer listening={false}>
                <Rect ref={band} visible={false} fill="rgba(250,204,21,0.12)" stroke="#facc15" strokeWidth={1.5} dash={[6, 4]} />
              </Layer>
            )}
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
