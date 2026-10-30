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
import { blendViewport, fitView, marginFor, viewRect, zoomTo, type Viewport } from "../../../lib/tactics/geometry.ts";
import type { Point } from "../../../lib/tactics/model.ts";
import { cameraAt, spotlightAt } from "../../../lib/tactics/marks.ts";
import { lookOf } from "../../../lib/tactics/pitch-style.ts";
import { objectsAt } from "../../../lib/tactics/timeline.ts";
import { ObjectNode } from "../objects/ObjectNode.tsx";
import { activeBoard, activeObjects, isBetween, useEditor } from "../store.ts";
import { DraftNode } from "./DraftNode.tsx";
import { Ghosts } from "./Ghosts.tsx";
import { Pitch, tiltedReach } from "./Pitch.tsx";
import { Selection } from "./Selection.tsx";
import { Marks } from "./Marks.tsx";
import { MeMarker } from "./MeMarker.tsx";
import { isMe } from "../../../lib/tactics/me.ts";
import { SpotlightLayer } from "./SpotlightLayer.tsx";
import { Figures3D, STANDING } from "./Figures3D.tsx";
import { drawnGround, groundReach, projector, TILT, tiltOrigin, tiltTransform, unproject, type Reach } from "../../../lib/tactics/projection.ts";
import { pitchPointer, StageContext, stageHolder, type StageShared } from "./stage-context.ts";
import { tiltHolder } from "./tilt-picture.ts";
import { useBand } from "./use-band.ts";
import { useSwipe } from "./use-swipe.ts";
import { isDrawTool, isPlaceTool, useDrawing } from "./use-drawing.ts";
import { IDENTITY, useViewport } from "./use-viewport.ts";

// A drag moves one node; Konva need not rebuild its hit map on every step.
// Pinching is read from the browser's own touch events instead.
Konva.hitOnDragEnabled = false;
// Sharper than 2× costs more than it shows on a tablet.
if (typeof window !== "undefined") Konva.pixelRatio = Math.min(window.devicePixelRatio || 1, 2);
const SHARP = Konva.pixelRatio;

const NO_REACH: Reach = { left: 0, top: 0, right: 0, bottom: 0 };

/**
 * extra: drawn over the objects, in metres (a live lesson's pointer and drawings).
 * moveOnly: objects can be dragged and nothing else (a participant given the floor).
 * onSwipe, onTap: watching only: a swipe sideways (not zoomed in) and a tap on the board (use-swipe).
 * tiltButton: 3D among the zoom buttons, for a shared link without the editor's timeline button.
 * tools: more buttons on the board's top right corner (a shared link's full screen, arena).
 * portrait: a wide view turned upright whatever the frame's shape (a phone).
 */
export default function BoardStage({ editable = true, moveOnly = false, extra, onSwipe, onTap, tiltButton = false, tools, portrait = false }: {
  editable?: boolean; moveOnly?: boolean; extra?: React.ReactNode; onSwipe?: (direction: 1 | -1) => void; onTap?: () => void; tiltButton?: boolean;
  tools?: React.ReactNode; portrait?: boolean;
}) {
  const frame = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState({ width: 0, height: 0 });
  const board = useEditor(activeBoard);
  const branding = useEditor(state => state.document?.branding);
  const objects = useEditor(activeObjects);
  const selection = useEditor(state => state.selection);
  const tool = useEditor(state => state.tool);
  const playing = useEditor(state => state.playing);
  const playhead = useEditor(state => state.playhead);
  const frameIndex = useEditor(state => state.frameIndex);
  const between = useEditor(isBetween);
  // Nothing is edited while the board plays or stands between two frames.
  const tilt = useEditor(state => state.tilt);
  const me = useEditor(state => state.me);
  const plain = useEditor(state => state.plain);
  const surroundings = plain ? undefined : board?.surroundings;
  // Nothing is edited tilted either: the screen no longer matches the pitch under the finger.
  const canEdit = editable && !playing && !between && !tilt;
  // Everything but dragging: selecting with a band, handles, the bin, tools.
  const fullEdit = canEdit && !moveOnly;
  const content = useRef<Konva.Group>(null);
  const nodes = useRef(new Map<string, Konva.Node>());
  const trash = useRef<HTMLDivElement>(null);
  const band = useBand(nodes.current);
  // 3D: a finger or the mouse moves the pitch under it, read back through the tilt.
  const tiltPan = useRef<{ from: Point; start: Viewport } | null>(null);
  const view = useViewport(frame, size.width > 0, [board?.id, board?.view, surroundings, portrait, size.width, size.height], () => {
    band.cancel();
    nodes.current.forEach(node => { if (node.isDragging()) node.stopDrag(); });
    tiltPan.current = null;
    swipe.cancel();
  }, tilt);
  const swipe = useSwipe(!editable, view.viewport.scale > 1.001, onSwipe, onTap);
  const stage = useRef<Konva.Stage | null>(null);
  // The tilted ground's canvas reaches far past the frame: drawn at 1×, it costs a quarter as much.
  useEffect(() => {
    stage.current?.getLayers().forEach(layer => { layer.getCanvas().setPixelRatio(tilt ? 1 : SHARP); layer.batchDraw(); });
  }, [tilt, size.width > 0]);

  useEffect(() => {
    const element = frame.current;
    if (!element) return;
    const observer = new ResizeObserver(([entry]) => setSize({ width: entry.contentRect.width, height: entry.contentRect.height }));
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  const fit = useMemo(() => fitView(viewRect(board?.view ?? "full", marginFor(surroundings)), size.width, size.height, portrait),
    [board?.view, surroundings, portrait, size.width, size.height]);
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
  const pannable = zoomedIn && !tilt && (tool === "select" || isPlaceTool(tool));
  const bandable = fullEdit && tool === "select" && !zoomedIn;
  // Hidden objects stay in the list, not on the pitch. Playing shows the moves.
  const shown = playing || between ? objectsAt(board.frames, playhead) : objects;
  const visible = shown.filter(item => !item.hidden);
  const holders = ballHolders(visible);
  // Ghosts of the frame before are for editing; a shared board shows none.
  const previous = fullEdit && frameIndex > 0 ? board.frames[frameIndex - 1]?.objects : undefined;
  const fitted = { x: fit.x, y: fit.y, scaleX: fit.scale, scaleY: fit.scale, rotation: fit.rotation };
  const onScreen = (event: { clientX: number; clientY: number }) => {
    const rect = frame.current?.getBoundingClientRect();
    const at = { x: event.clientX - (rect?.left ?? 0), y: event.clientY - (rect?.top ?? 0) };
    return tilt ? unproject(at, size.width, size.height) : at;
  };
  // Playing into a frame that zooms, the view leaves the user's zoom for the object.
  const camera = playing || between ? cameraAt(board.frames, playhead, shown) : null;
  const sight = camera ? blendViewport(view.viewport, zoomTo(camera.at, fit, size.width, size.height, camera.scale), camera.amount) : view.viewport;
  const zoomed = { x: sight.x, y: sight.y, scaleX: sight.scale, scaleY: sight.scale };
  const reach = tilt ? groundReach(size.width, size.height, drawnGround(fit, sight, tiltedReach(surroundings))) : NO_REACH;
  const offset = { x: reach.left, y: reach.top };
  tiltHolder.offset = offset;
  const spotlight = playing || between ? spotlightAt(board.frames, playhead, shown) : null;
  // 3D: the ground keeps what lies on it; what stands up is drawn upright over it.
  const onGround = tilt ? visible.filter(item => !STANDING.has(item.type)) : visible;
  const tapGrass = (target: Konva.Node) => {
    if (isPlaceTool(tool)) drawing.place();
    else if (tool === "select" && target.name() === "grass") useEditor.getState().select([]);
  };

  return (
    <div ref={frame} className="tb-stage" data-tool={tool} data-tilt={tilt} style={tilt ? { perspective: `${TILT.perspective}px` } : undefined}
      onPointerDown={event => {
        swipe.down(event);
        if (!tilt || !zoomedIn || view.pinch.current) return;
        tiltPan.current = { from: onScreen(event), start: view.live.current };
        event.currentTarget.setPointerCapture(event.pointerId);
      }}
      onPointerMove={event => {
        const pan = tiltPan.current;
        if (!pan) return;
        if (view.pinch.current) { tiltPan.current = null; return; }
        const at = onScreen(event);
        view.apply({ ...pan.start, x: pan.start.x + at.x - pan.from.x, y: pan.start.y + at.y - pan.from.y }, false);
      }}
      onPointerUp={event => {
        swipe.up(event);
        if (tiltPan.current) { tiltPan.current = null; view.apply(view.live.current, true); }
      }}
      onPointerCancel={() => { swipe.cancel(); tiltPan.current = null; }}>
      {/* Konva fails drawing into a board without width or height (a phone with the panel open). */}
      {size.width > 0 && size.height > 0 && (
        <StageContext.Provider value={shared}>
          <div className="tb-ground" style={tilt ? { transform: tiltTransform, transformOrigin: tiltOrigin } : undefined}>
          <Stage ref={node => { stageHolder.current = node; stage.current = node; }}
            width={size.width + reach.left + reach.right} height={size.height + reach.top + reach.bottom}
            style={tilt ? { position: "absolute", left: -reach.left, top: -reach.top } : undefined}
            onWheel={event => {
              event.evt.preventDefault();
              const at = tilt ? onScreen(event.evt) : event.target.getStage()?.getPointerPosition();
              if (at) view.zoomBy(event.evt.deltaY > 0 ? 1 / 1.12 : 1.12, at);
            }}
            onPointerDown={event => {
              if (view.pinch.current) return;
              if (fullEdit && isDrawTool(tool)) drawing.start();
              else if (bandable && event.target.name() === "grass") band.begin(event);
            }}
            onPointerMove={event => {
              drawing.move();
              band.move(event);
              if (pitchPointer.size) { const at = content.current?.getRelativePointerPosition() ?? null; pitchPointer.forEach(listen => listen(at)); }
            }}
            onPointerLeave={() => pitchPointer.forEach(listen => listen(null))}
            onPointerUp={event => { drawing.end(); band.end(event, visible.map(item => item.id)); }}
            onClick={event => {
              if (band.consumeClick() || event.evt.button !== 0 || !fullEdit) return;
              tapGrass(event.target);
            }}
            onTap={event => {
              if (band.consumeClick() || !fullEdit || view.pinch.current) return;
              tapGrass(event.target);
            }}>
            <Layer {...offset}>
              <Group ref={view.pitchView} {...zoomed} draggable={pannable}
                onDragMove={event => view.panMove({ x: event.target.x(), y: event.target.y() })}
                onDragEnd={view.panEnd}>
                <Group {...fitted}>
                  <Pitch view={board.view} overlay={board.overlay} style={board.pitch} surroundings={surroundings} branding={branding} upright={upright} tilted={tilt} />
                </Group>
              </Group>
            </Layer>
            <Layer {...offset}>
              <Group ref={view.objectView} {...zoomed}>
                <Group ref={content} {...fitted}>
                  {previous && <Ghosts previous={previous} current={objects} selection={selection} editable={canEdit} ink={lookOf(board.pitch).ink} />}
                  <Marks objects={visible} board={board} />
                  {visible.filter(item => isMe(item, me)).map(item => <MeMarker key={`me-${item.id}`} at={item} upright={upright} label={!tilt} />)}
                  {onGround.map(item => (
                    <ObjectNode key={item.id} item={item} board={board} selected={selection.includes(item.id)} upright={upright} holding={holders.has(item.id)} />
                  ))}
                  {fullEdit && <Selection objects={objects} selection={selection} upright={upright} facing={board.showFacing ?? false} />}
                  {drawing.draft && <DraftNode draft={drawing.draft} ink={lookOf(board.pitch).ink} />}
                  {extra}
                </Group>
              </Group>
            </Layer>
            {!tilt && <SpotlightLayer spotlight={spotlight} zoomed={zoomed} fitted={fitted} />}
            {fullEdit && (
              <Layer listening={false}>
                <Rect ref={band.band} visible={false} fill="rgba(250,204,21,0.12)" stroke="#facc15" strokeWidth={1.5} dash={[6, 4]} />
              </Layer>
            )}
          </Stage>
          </div>
          {tilt && <Figures3D objects={visible} board={board} project={projector(fit, sight, size.width, size.height)} spotlight={spotlight} width={size.width} height={size.height} me={me}
            stageRef={node => { tiltHolder.figures = node; }} />}
        </StageContext.Provider>
      )}
      {fullEdit && (
        <div ref={trash} className="tb-trash" data-active="false" data-over="false" aria-hidden="true">
          <span>🗑</span>Släpp för att ta bort
        </div>
      )}
      {tools && <div className="tb-board-tools">{tools}</div>}
      <div className="tb-zoom" role="group" aria-label="Zoom">
        <button type="button" onClick={() => view.zoomBy(1.25, { x: size.width / 2, y: size.height / 2 })} aria-label="Zooma in">+</button>
        <button type="button" onClick={() => view.zoomBy(0.8, { x: size.width / 2, y: size.height / 2 })} aria-label="Zooma ut">−</button>
        {tiltButton && <button type="button" className="tb-zoom-tilt" aria-pressed={tilt} onClick={() => useEditor.getState().setTilt(!tilt)} aria-label="3D" title="Planen sedd snett från läktaren">3D</button>}
        <button type="button" onClick={() => view.apply(IDENTITY, true)} aria-label="Visa hela" disabled={view.viewport === IDENTITY}>⤢</button>
      </div>
    </div>
  );
}
