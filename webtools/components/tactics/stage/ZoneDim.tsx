"use client";

// Lit areas (a zone, rectangle or ellipse with dim set): everything round
// them dimmed, players too, each area left clear with a wide soft rim where
// the dark fades in, as the spotlight's does. Drawn on the objects' own
// layer after the objects and before the selection's handles, which stay
// bright over it. The dark is only a shadow: the shape that casts it is drawn
// far off the canvas, so its blur alone falls on the pitch, softening every
// edge alike. No edge is drawn, but round a selected area, to show where it is
// being changed. Drawn as the layer is, it follows an area being dragged, by
// itself or by a corner, before the drop is written.
import type { Context } from "konva/lib/Context";
import { Shape } from "react-konva";
import { PITCH_LENGTH, PITCH_WIDTH, type Point, type ShapeObject, type ZoneObject } from "../../../lib/tactics/model.ts";
import type { Rendered } from "../../../lib/tactics/timeline.ts";
import { zoneOutline } from "../../../lib/tactics/zone.ts";
import { shaped } from "../objects/ZoneNode.tsx";
import { useZoneMoving } from "../objects/zone-moving.ts";
import { useStage } from "./stage-context.ts";

/** How dark it is outside a lit area. */
export const ZONE_DIM = 0.55;
/** How wide the soft rim between dark and clear is, about, in metres; half of it inside the edge. */
const FEATHER = 4;
/** How far past the canvas's right edge the dark's shape is drawn, beyond its blur, in canvas pixels. */
const AWAY = 200;
/** The dark's shape: the pitch and well round it, in metres. */
const DARK = { x: -200, y: -200, width: PITCH_LENGTH + 400, height: PITCH_WIDTH + 400 };
/** Round an ellipse in this many points. */
const ROUND = 64;

type Lit = (ZoneObject | ShapeObject) & Rendered;

export const litAreas = (objects: Rendered[]) =>
  objects.filter((item): item is Lit => (item.type === "zone" || item.type === "rect" || item.type === "ellipse") && !!item.dim);

/** Where an area is just now: its node's place while it is dragged. */
type Place = { x: number; y: number; rotation: number };

/** The area's edge on the pitch, in metres. */
function edgeOf(item: Lit, place: Place): Point[] {
  let edge: Point[];
  if (item.type === "zone") edge = zoneOutline(item);
  else if (item.type === "rect") {
    const [w, h] = [item.width / 2, item.height / 2];
    edge = [{ x: -w, y: -h }, { x: w, y: -h }, { x: w, y: h }, { x: -w, y: h }];
  } else edge = Array.from({ length: ROUND }, (_, step) => ({ x: (Math.cos((step / ROUND) * Math.PI * 2) * item.width) / 2, y: (Math.sin((step / ROUND) * Math.PI * 2) * item.height) / 2 }));
  const turn = (place.rotation * Math.PI) / 180, cos = Math.cos(turn), sin = Math.sin(turn);
  return edge.map(point => ({ x: place.x + point.x * cos - point.y * sin, y: place.y + point.x * sin + point.y * cos }));
}

const trace = (native: CanvasRenderingContext2D, edge: Point[]) => {
  edge.forEach((point, index) => (index === 0 ? native.moveTo(point.x, point.y) : native.lineTo(point.x, point.y)));
  native.closePath();
};

/** The dark round the lit areas, in pitch metres; selected: the ids whose edge is shown. */
export function ZoneDim({ objects, selected = [] }: { objects: Rendered[]; selected?: string[] }) {
  const shared = useStage();
  const moving = useZoneMoving(state => state.moving);
  const lit = litAreas(objects).map(item => (item.type === "zone" && moving?.id === item.id ? { ...item, ...shaped(item, moving) } : item));
  const strength = Math.max(0, ...lit.map(item => item.opacity ?? 1));
  if (strength <= 0) return null;
  const placeOf = (item: Lit): Place => {
    const node = shared.nodes.get(item.id);
    return node?.isDragging() ? { x: node.x(), y: node.y(), rotation: node.rotation() } : item;
  };
  const draw = (context: Context) => {
    // An area fading out leaves the dark whole once it is more gone than there.
    const holes = lit.filter(item => (item.opacity ?? 1) >= strength / 2).map(item => edgeOf(item, placeOf(item)));
    const native = context._context as CanvasRenderingContext2D;
    const m = native.getTransform();
    const blur = FEATHER * Math.hypot(m.a, m.b);
    // Wholly off the canvas, however far in it is zoomed: its leftmost corner past the right edge.
    const corners = [[DARK.x, DARK.y], [DARK.x + DARK.width, DARK.y], [DARK.x, DARK.y + DARK.height], [DARK.x + DARK.width, DARK.y + DARK.height]];
    const left = Math.min(...corners.map(([x, y]) => m.a * x + m.c * y + m.e));
    const away = Math.max(0, native.canvas.width - left) + blur * 3 + AWAY;
    native.save();
    native.setTransform(m.a, m.b, m.c, m.d, m.e + away, m.f);
    native.beginPath();
    native.rect(DARK.x, DARK.y, DARK.width, DARK.height);
    for (const hole of holes) trace(native, hole);
    native.shadowColor = `rgba(5,8,12,${ZONE_DIM * strength})`;
    native.shadowBlur = blur;
    native.shadowOffsetX = -away;
    native.shadowOffsetY = 0;
    native.fillStyle = "#000000";
    native.fill("evenodd");
    native.restore();
    // A selected area's edge, over the dark.
    for (const item of lit.filter(area => selected.includes(area.id))) {
      native.save();
      native.beginPath();
      trace(native, edgeOf(item, placeOf(item)));
      native.strokeStyle = item.color;
      native.lineWidth = 0.25;
      native.lineJoin = "round";
      native.setLineDash(item.dashed ? [0.9, 0.6] : []);
      native.stroke();
      native.restore();
    }
  };
  return <Shape sceneFunc={draw} listening={false} perfectDrawEnabled={false} />;
}
