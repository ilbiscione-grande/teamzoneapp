"use client";

// Lit areas (a zone, rectangle or ellipse with dim set): everything round
// them dimmed, players too, each area left clear with the dark fading in
// softly past its edge, as the spotlight's does; the edge itself drawn again
// over the dark. On a canvas of its own (ZoneDimLayer) over the objects, so
// its holes cut only its own dark; fading areas fade the dark with them.
import type Konva from "konva";
import type { Ref } from "react";
import { Ellipse, Group, Layer, Line, Rect } from "react-konva";
import { PITCH_LENGTH, PITCH_WIDTH, type ShapeObject, type ZoneObject } from "../../../lib/tactics/model.ts";
import type { Rendered } from "../../../lib/tactics/timeline.ts";
import { zoneOutline } from "../../../lib/tactics/zone.ts";

/** How dark it is outside a lit area. */
export const ZONE_DIM = 0.55;
/** How far past the edge the dark takes to come in, in metres. */
const FEATHER = 2.5;

type Transform = { x: number; y: number; scaleX: number; scaleY: number; rotation?: number };
type Lit = (ZoneObject | ShapeObject) & Rendered;

const litAreas = (objects: Rendered[]) =>
  objects.filter((item): item is Lit => (item.type === "zone" || item.type === "rect" || item.type === "ellipse") && !!item.dim);

/** The area's shape, about its own x and y, drawn with these attributes. */
function Area({ item, ...attrs }: { item: Lit } & Record<string, unknown>) {
  if (item.type === "zone") return <Line points={zoneOutline(item).flatMap(point => [point.x, point.y])} closed {...attrs} />;
  if (item.type === "rect") return <Rect width={item.width} height={item.height} offsetX={item.width / 2} offsetY={item.height / 2} cornerRadius={0.4} {...attrs} />;
  return <Ellipse radiusX={item.width / 2} radiusY={item.height / 2} {...attrs} />;
}

/** The dark and its holes, in pitch metres. */
export function ZoneDim({ objects }: { objects: Rendered[] }) {
  const lit = litAreas(objects);
  const strength = Math.max(0, ...lit.map(item => item.opacity ?? 1));
  if (strength <= 0) return null;
  const quiet = { listening: false, perfectDrawEnabled: false };
  return (
    <Group listening={false}>
      <Rect x={-200} y={-200} width={PITCH_LENGTH + 400} height={PITCH_WIDTH + 400} fill="#05080c" opacity={ZONE_DIM * strength} listening={false} />
      {lit.map(item => (
        <Group key={item.id} x={item.x} y={item.y} rotation={item.rotation} listening={false}>
          {/* Clear inside; the shadow clears less and less past the edge, so the dark comes in softly. */}
          <Area item={item} {...quiet} fill="#000000" opacity={(item.opacity ?? 1) / strength} globalCompositeOperation="destination-out"
            shadowColor="#000000" shadowBlur={FEATHER} shadowOpacity={1} shadowForStrokeEnabled={false} />
          <Area item={item} {...quiet} stroke={item.color} strokeWidth={0.25} opacity={item.opacity ?? 1} dash={item.dashed ? [0.9, 0.6] : undefined} lineJoin="round" />
        </Group>
      ))}
    </Group>
  );
}

/** Lit areas' dimming over the board's objects, moved and zoomed as they are. */
export function ZoneDimLayer({ objects, zoomed, fitted, offset, viewRef }: {
  objects: Rendered[]; zoomed: Transform; fitted: Transform; offset?: { x: number; y: number }; viewRef?: Ref<Konva.Group>;
}) {
  if (litAreas(objects).length === 0) return null;
  return (
    <Layer listening={false} {...offset}>
      <Group ref={viewRef} {...zoomed}>
        <Group {...fitted}>
          <ZoneDim objects={objects} />
        </Group>
      </Group>
    </Layer>
  );
}
