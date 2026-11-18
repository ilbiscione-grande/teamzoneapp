// A zone of one's own shape (ZoneObject): its corners placed one by one on
// the pitch and joined, closed when the first corner is tapped again, the
// last one tapped twice or Enter pressed. Placed at the middle of its
// corners, which are kept relative to it, so it moves as one; a corner can
// be dragged on its own afterwards.
import { newId } from "./document.ts";
import type { Point, ZoneObject } from "./model.ts";

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
