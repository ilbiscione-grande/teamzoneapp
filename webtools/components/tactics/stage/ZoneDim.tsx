"use client";

// Lit zones (ZoneObject.dim): everything round them dimmed, players too, each
// zone left clear with its edge drawn again over the dark. On a canvas of its
// own (ZoneDimLayer) over the objects, so its holes cut only its own dark;
// fading zones fade the dark with them.
import type Konva from "konva";
import type { Ref } from "react";
import { Group, Layer, Line, Rect } from "react-konva";
import { PITCH_LENGTH, PITCH_WIDTH, type ZoneObject } from "../../../lib/tactics/model.ts";
import type { Rendered } from "../../../lib/tactics/timeline.ts";
import { zoneOutline } from "../../../lib/tactics/zone.ts";

/** How dark it is outside a lit zone. */
export const ZONE_DIM = 0.55;

type Transform = { x: number; y: number; scaleX: number; scaleY: number; rotation?: number };

const litZones = (objects: Rendered[]) => objects.filter((item): item is ZoneObject & Rendered => item.type === "zone" && !!item.dim);

/** The dark and its holes, in pitch metres; on a layer of its own. */
export function ZoneDim({ objects }: { objects: Rendered[] }) {
  const lit = litZones(objects);
  const strength = Math.max(0, ...lit.map(item => item.opacity ?? 1));
  if (strength <= 0) return null;
  return (
    <Group listening={false}>
      <Rect x={-200} y={-200} width={PITCH_LENGTH + 400} height={PITCH_WIDTH + 400} fill="#05080c" opacity={ZONE_DIM * strength} listening={false} />
      {lit.map(item => {
        const points = zoneOutline(item).flatMap(point => [point.x, point.y]);
        const place = { x: item.x, y: item.y, rotation: item.rotation, points, closed: true, listening: false, perfectDrawEnabled: false };
        return (
          <Group key={item.id} listening={false}>
            <Line {...place} fill="#000000" opacity={(item.opacity ?? 1) / strength} globalCompositeOperation="destination-out" />
            {/* The edge again, as the dark took its outer half. */}
            <Line {...place} stroke={item.color} strokeWidth={0.8} opacity={0.25 * (item.opacity ?? 1)} lineJoin="round" />
            <Line {...place} stroke={item.color} strokeWidth={0.25} opacity={item.opacity ?? 1} dash={item.dashed ? [0.9, 0.6] : undefined} lineJoin="round" />
          </Group>
        );
      })}
    </Group>
  );
}

/** Lit zones' dimming over the board's objects, moved and zoomed as they are. */
export function ZoneDimLayer({ objects, zoomed, fitted, offset, viewRef }: {
  objects: Rendered[]; zoomed: Transform; fitted: Transform; offset?: { x: number; y: number }; viewRef?: Ref<Konva.Group>;
}) {
  if (litZones(objects).length === 0) return null;
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
