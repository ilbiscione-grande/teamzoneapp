"use client";

// The board: the pitch fitted to its frame (turned on a tall screen), with
// zoom by pinching, the mouse wheel or the buttons (use-viewport). With the
// whole view in sight, dragging over the grass draws a band that selects
// what it touches (use-band); zoomed in, it moves around the pitch instead.
// The pitch has a layer of its own that never redraws while an object
// moves. While something is dragged, a bin beside the pitch removes it.
import Konva from "konva";
import { useEffect, useMemo, useRef, useState } from "react";
import { Group, Layer, Rect, Stage } from "react-konva";
import { ballHolders } from "../../../lib/tactics/ball.ts";
import { fitView, viewRect } from "../../../lib/tactics/geometry.ts";
import { objectsAt } from "../../../lib/tactics/timeline.ts";
import { ObjectNode } from "../objects/ObjectNode.tsx";
import { activeBoard, activeObjects, isBetween, useEditor } from "../store.ts";
import { DraftNode } from "./DraftNode.tsx";
import { Ghosts } from "./Ghosts.tsx";
import { Pitch } from "./Pitch.tsx";
import { Selection } from "./Selection.tsx";
import { StageContext, stageHolder, type StageShared } from "./stage-context.ts";
import { useBand } from "./use-band.ts";
import { isDrawTool, isPlaceTool, useDrawing } from "./use-drawing.ts";
import { IDENTITY, useViewport } from "./use-viewport.ts";

// A drag moves one node; Konva need not rebuild its hit map on every step.
// Pinching is read from the browser's own touch events instead.
Konva.hitOnDragEnabled = false;
// Sharper than 2× costs more than it shows on a tablet.
if (typeof window !== "undefined") Konva.pixelRatio = Math.min(window.devicePixelRatio || 1, 2);

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
  const between = useEditor(isBetween);
  // Nothing is edited while the board plays or stands between two frames.
  const canEdit = editable && !playing && !between;
  const content = useRef<Konva.Group>(null);
  const nodes = useRef(new Map<string, Konva.Node>());
  const trash = useRef<HTMLDivElement>(null);
  const band = useBand(nodes.current);
  const view = useViewport(frame, size.width > 0, [board?.id, board?.view, size.width, size.height], () => {
    band.cancel();
    nodes.current.forEach(node => { if (node.isDragging()) node.stopDrag(); });
  });

  useEffect(() => {
    const element = frame.current;
    if (!element) return;
    const observer = new ResizeObserver(([entry]) => setSize({ width: entry.contentRect.width, height: entry.contentRect.height }));
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  const fit = useMemo(() => fitView(viewRect(board?.view ?? "full"), size.width, size.height), [board?.view, size.width, size.height]);
  const shared = useMemo<StageShared>(() => ({
    nodes: nodes.current,
    content,
    metresPerPixel: () => 1 / (fit.scale * view.live.current.scale || 1),
    editable: canEdit,
    trash,
  }), [fit.scale, canEdit, view.live]);

  const drawing = useDrawing(() => content.current?.getRelativePointerPosition() ?? null);

  if (!board) return <div ref={frame} className="tb-stage" />;
  const upright = -fit.rotation;
  // Zoomed in, the grass moves the view; with the whole view in sight it selects.
  const zoomedIn = view.viewport.scale > 1.001;
  const pannable = zoomedIn && (tool === "select" || isPlaceTool(tool));
  const bandable = canEdit && tool === "select" && !zoomedIn;
  // Hidden objects stay in the list, not on the pitch. Playing shows the moves.
  const shown = playing || between ? objectsAt(board.frames, playhead) : objects;
  const visible = shown.filter(item => !item.hidden);
  const holders = ballHolders(visible);
  // Ghosts of the frame before are for editing; a shared board shows none.
  const previous = canEdit && frameIndex > 0 ? board.frames[frameIndex - 1]?.objects : undefined;
  const fitted = { x: fit.x, y: fit.y, scaleX: fit.scale, scaleY: fit.scale, rotation: fit.rotation };
  const zoomed = { x: view.viewport.x, y: view.viewport.y, scaleX: view.viewport.scale, scaleY: view.viewport.scale };
  const tapGrass = (target: Konva.Node) => {
    if (isPlaceTool(tool)) drawing.place();
    else if (tool === "select" && target.name() === "grass") useEditor.getState().select([]);
  };

  return (
    <div ref={frame} className="tb-stage" data-tool={tool}>
      {/* Konva fails drawing into a board without width or height (a phone with the panel open). */}
      {size.width > 0 && size.height > 0 && (
        <StageContext.Provider value={shared}>
          <Stage ref={node => { stageHolder.current = node; }} width={size.width} height={size.height}
            onWheel={event => {
              event.evt.preventDefault();
              const at = event.target.getStage()?.getPointerPosition();
              if (at) view.zoomBy(event.evt.deltaY > 0 ? 1 / 1.12 : 1.12, at);
            }}
            onPointerDown={event => {
              if (view.pinch.current) return;
              if (canEdit && isDrawTool(tool)) drawing.start();
              else if (bandable && event.target.name() === "grass") band.begin(event);
            }}
            onPointerMove={event => { drawing.move(); band.move(event); }}
            onPointerUp={event => { drawing.end(); band.end(event, visible.map(item => item.id)); }}
            onClick={event => {
              if (band.consumeClick() || event.evt.button !== 0 || !canEdit) return;
              tapGrass(event.target);
            }}
            onTap={event => {
              if (band.consumeClick() || !canEdit || view.pinch.current) return;
              tapGrass(event.target);
            }}>
            <Layer>
              <Group ref={view.pitchView} {...zoomed} draggable={pannable}
                onDragMove={event => view.panMove({ x: event.target.x(), y: event.target.y() })}
                onDragEnd={view.panEnd}>
                <Group {...fitted}>
                  <Pitch view={board.view} overlay={board.overlay} />
                </Group>
              </Group>
            </Layer>
            <Layer>
              <Group ref={view.objectView} {...zoomed}>
                <Group ref={content} {...fitted}>
                  {previous && <Ghosts previous={previous} current={objects} selection={selection} editable={canEdit} />}
                  {visible.map(item => (
                    <ObjectNode key={item.id} item={item} board={board} selected={selection.includes(item.id)} upright={upright} holding={holders.has(item.id)} />
                  ))}
                  {canEdit && <Selection objects={objects} selection={selection} upright={upright} />}
                  {drawing.draft && <DraftNode draft={drawing.draft} />}
                </Group>
              </Group>
            </Layer>
            {canEdit && (
              <Layer listening={false}>
                <Rect ref={band.band} visible={false} fill="rgba(250,204,21,0.12)" stroke="#facc15" strokeWidth={1.5} dash={[6, 4]} />
              </Layer>
            )}
          </Stage>
        </StageContext.Provider>
      )}
      {canEdit && (
        <div ref={trash} className="tb-trash" data-active="false" data-over="false" aria-hidden="true">
          <span>🗑</span>Släpp för att ta bort
        </div>
      )}
      <div className="tb-zoom" role="group" aria-label="Zoom">
        <button type="button" onClick={() => view.zoomBy(1.25, { x: size.width / 2, y: size.height / 2 })} aria-label="Zooma in">+</button>
        <button type="button" onClick={() => view.zoomBy(0.8, { x: size.width / 2, y: size.height / 2 })} aria-label="Zooma ut">−</button>
        <button type="button" onClick={() => view.apply(IDENTITY, true)} aria-label="Visa hela" disabled={view.viewport === IDENTITY}>⤢</button>
      </div>
    </div>
  );
}
