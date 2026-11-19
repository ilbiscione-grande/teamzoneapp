// A zone of one's own shape (ZoneObject): its corners placed one by one on
// the pitch and joined, closed when the first corner is tapped again, the
// last one tapped twice or Enter pressed. Placed at the middle of its
// corners, which are kept relative to it, so it moves as one; a corner can
// be dragged on its own afterwards, and each side bent by its middle, as an
// arrow is.
import { newId } from "./document.ts";
import type { Point, ZoneObject } from "./model.ts";
import { curvePoint, lerpPoint } from "./motion.ts";
import { controlThrough, curveMiddle } from "./path.ts";

/** The least a zone has. */
export const MIN_CORNERS = 3;

/** A zone through these corners, or null with too few that are apart. */
export function zoneFrom(corners: Point[]): ZoneObject | null {
  const apart = corners.filter((point, index) => index === 0 || Math.hypot(point.x - corners[index - 1].x, point.y - corners[index - 1].y) > 0.05);
  if (apart.length < MIN_CORNERS) return null;
  const xs = apart.map(point => point.x), ys = apart.map(point => point.y);
  const middle = { x: (Math.min(...xs) + Math.max(...xs)) / 2, y: (Math.min(...ys) + Math.max(...ys)) / 2 };
  return {
    id: newId(), type: "zone", x: middle.x, y: middle.y, rotation: 0, locked: false, hidden: false,
    points: apart.flatMap(point => [point.x - middle.x, point.y - middle.y]), color: "#facc15", fill: 0.35, dashed: false,
  };
}

/** The corners, relative to x and y. */
export function cornersOf(zone: Pick<ZoneObject, "points">): Point[] {
  const corners: Point[] = [];
  for (let index = 0; index + 1 < zone.points.length; index += 2) corners.push({ x: zone.points[index], y: zone.points[index + 1] });
  return corners;
}

/** The zone's points with one corner moved to a place relative to x and y. */
export function moveCorner(zone: Pick<ZoneObject, "points">, index: number, to: Point): number[] {
  return zone.points.map((value, at) => (at === index * 2 ? to.x : at === index * 2 + 1 ? to.y : value));
}

/**
 * The bends once a corner has moved: the two sides it ends keep their bend,
 * moved half as far, so a bent side keeps its shape as it is stretched.
 */
export function bendsAfterCorner(zone: Pick<ZoneObject, "points" | "bends">, index: number, to: Point): (Point | null)[] | undefined {
  if (!zone.bends) return zone.bends;
  const count = cornersOf(zone).length;
  const from = cornersOf(zone)[index];
  const shift = { x: (to.x - from.x) / 2, y: (to.y - from.y) / 2 };
  const before = (index - 1 + count) % count;
  return zone.bends.map((bend, side) => (bend && (side === index || side === before) ? { x: bend.x + shift.x, y: bend.y + shift.y } : bend));
}

/** Side `side` of a zone: from its corner to the next, with its bend. */
export function sideOf(zone: Pick<ZoneObject, "points" | "bends">, side: number): { from: Point; to: Point; control: Point | null } {
  const corners = cornersOf(zone);
  return { from: corners[side], to: corners[(side + 1) % corners.length], control: zone.bends?.[side] ?? null };
}

/** The point halfway along a side: where its handle is. */
export const sideMiddle = (zone: Pick<ZoneObject, "points" | "bends">, side: number) => {
  const { from, to, control } = sideOf(zone, side);
  return curveMiddle(from, to, control);
};

/** The bends with one side bent through a point (relative to x and y), or straightened with null. */
export function bendSide(zone: Pick<ZoneObject, "points" | "bends">, side: number, through: Point | null): (Point | null)[] {
  const count = cornersOf(zone).length;
  const bends = Array.from({ length: count }, (_, index) => zone.bends?.[index] ?? null);
  const { from, to } = sideOf(zone, side);
  bends[side] = through ? controlThrough(from, to, through) : null;
  return bends;
}

/** The zone's edge as points relative to x and y, a bent side in short steps; closed back to the first. */
export function zoneOutline(zone: Pick<ZoneObject, "points" | "bends">, steps = 16): Point[] {
  const count = cornersOf(zone).length;
  const outline: Point[] = [];
  for (let side = 0; side < count; side++) {
    const { from, to, control } = sideOf(zone, side);
    outline.push(from);
    if (control) for (let step = 1; step < steps; step++) outline.push(curvePoint(from, to, control, step / steps));
  }
  return outline;
}

/** The bends between two frames' copies of a zone: each side's bend part of the way, a straight side bending from its middle. */
export function blendBends(prev: Pick<ZoneObject, "points" | "bends">, next: Pick<ZoneObject, "points" | "bends">, t: number): (Point | null)[] | undefined {
  if (!prev.bends && !next.bends) return undefined;
  const count = cornersOf(next).length;
  return Array.from({ length: count }, (_, side) => {
    const a = prev.bends?.[side] ?? null, b = next.bends?.[side] ?? null;
    if (!a && !b) return null;
    const straight = (zone: typeof prev) => { const { from, to } = sideOf(zone, side); return lerpPoint(from, to, 0.5); };
    return lerpPoint(a ?? straight(prev), b ?? straight(next), t);
  });
}

/**
 * What a tap does while placing corners: closes the zone on the first corner
 * or on the last one tapped again (a double tap), once it has enough; else
 * adds a corner. reach: how near counts as on a corner, in metres.
 */
export function tapCorner(corners: Point[], at: Point, reach: number): { corners: Point[]; close: boolean } {
  const near = (point: Point | undefined) => !!point && Math.hypot(point.x - at.x, point.y - at.y) <= reach;
  if (corners.length >= MIN_CORNERS && (near(corners[0]) || near(corners[corners.length - 1]))) return { corners, close: true };
  if (near(corners[corners.length - 1])) return { corners, close: false };
  return { corners: [...corners, at], close: false };
}

/** Where on a side a point is nearest: the side, how far along it (0 to 1) and how far off, relative to x and y. */
export function nearestOnEdge(zone: Pick<ZoneObject, "points" | "bends">, at: Point, steps = 48): { side: number; t: number; distance: number } {
  const count = cornersOf(zone).length;
  let best = { side: 0, t: 0.5, distance: Infinity };
  for (let side = 0; side < count; side++) {
    const { from, to, control } = sideOf(zone, side);
    for (let step = 1; step < steps; step++) {
      const t = step / steps;
      const point = control ? curvePoint(from, to, control, t) : lerpPoint(from, to, t);
      const distance = Math.hypot(point.x - at.x, point.y - at.y);
      if (distance < best.distance) best = { side, t, distance };
    }
  }
  return best;
}

/**
 * The zone with a corner put on its edge where it is nearest a point, the
 * side it is on split in two there: a bent side into two bent halves, so the
 * shape stays as it was.
 */
export function insertCorner(zone: Pick<ZoneObject, "points" | "bends">, at: Point): Pick<ZoneObject, "points" | "bends"> {
  const { side, t } = nearestOnEdge(zone, at);
  return splitSide(zone, side, t);
}

/** How long a side is along its bend. */
function sideLength(zone: Pick<ZoneObject, "points" | "bends">, side: number, steps = 16): number {
  const { from, to, control } = sideOf(zone, side);
  let length = 0, last = from;
  for (let step = 1; step <= steps; step++) {
    const point = control ? curvePoint(from, to, control, step / steps) : lerpPoint(from, to, step / steps);
    length += Math.hypot(point.x - last.x, point.y - last.y);
    last = point;
  }
  return length;
}

/** The zone with a corner more, in the middle of its longest side. */
export function addCorner(zone: Pick<ZoneObject, "points" | "bends">): Pick<ZoneObject, "points" | "bends"> {
  const count = cornersOf(zone).length;
  let longest = 0;
  for (let side = 1; side < count; side++) if (sideLength(zone, side) > sideLength(zone, longest)) longest = side;
  return splitSide(zone, longest, 0.5);
}

/** The zone with side `side` split in two by a corner t of the way along it. */
export function splitSide(zone: Pick<ZoneObject, "points" | "bends">, side: number, t: number): Pick<ZoneObject, "points" | "bends"> {
  const { from, to, control } = sideOf(zone, side);
  const corners = cornersOf(zone);
  let corner: Point, first: Point | null = null, second: Point | null = null;
  if (control) {
    first = lerpPoint(from, control, t);
    second = lerpPoint(control, to, t);
    corner = lerpPoint(first, second, t);
  } else corner = lerpPoint(from, to, t);
  corners.splice(side + 1, 0, corner);
  const points = corners.flatMap(point => [point.x, point.y]);
  if (!zone.bends && !control) return { points, bends: zone.bends };
  const bends = Array.from({ length: corners.length - 1 }, (_, index) => zone.bends?.[index] ?? null);
  bends.splice(side, 1, first, second);
  return { points, bends };
}
