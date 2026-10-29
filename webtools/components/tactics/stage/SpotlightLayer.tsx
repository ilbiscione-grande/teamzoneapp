"use client";

// The spotlight effect (lib/tactics/marks.ts spotlightAt): a layer of its
// own over the pitch and the objects, dark all over but for soft holes
// round the lit objects. Cut out on its own canvas, so the holes show the
// layers beneath as they are.
import { Circle, Group, Layer, Rect } from "react-konva";
import { PITCH_LENGTH, PITCH_WIDTH } from "../../../lib/tactics/model.ts";
import type { Spotlight } from "../../../lib/tactics/marks.ts";

/** How wide a lit spot is, in metres. */
const SPOT = 7;

type Transform = { x: number; y: number; scaleX: number; scaleY: number; rotation?: number };

export function SpotlightLayer({ spotlight, zoomed, fitted }: { spotlight: Spotlight | null; zoomed: Transform; fitted: Transform }) {
  if (!spotlight || spotlight.amount <= 0) return null;
  return (
    <Layer listening={false}>
      <Group {...zoomed}>
        <Group {...fitted}>
          <Rect x={-200} y={-200} width={PITCH_LENGTH + 400} height={PITCH_WIDTH + 400} fill="#05080c" opacity={0.6 * spotlight.amount} listening={false} />
          {spotlight.spots.map((spot, index) => (
            <Circle key={index} x={spot.x} y={spot.y} radius={SPOT} globalCompositeOperation="destination-out" listening={false}
              fillRadialGradientStartPoint={{ x: 0, y: 0 }} fillRadialGradientStartRadius={0}
              fillRadialGradientEndPoint={{ x: 0, y: 0 }} fillRadialGradientEndRadius={SPOT}
              fillRadialGradientColorStops={[0, "rgba(0,0,0,1)", 0.65, "rgba(0,0,0,1)", 1, "rgba(0,0,0,0)"]} />
          ))}
        </Group>
      </Group>
    </Layer>
  );
}
