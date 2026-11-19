// One area turning into another between frames: a zone, rectangle or
// ellipse new in a frame, set to be formed out of one gone from the frame
// before (morphFrom), flows out of that one's shape and place as the frames
// play, so a circle drawn in one frame turns into a triangle drawn in the
// next, and on into a zone of one's own in the one after. Areas not so linked
// fade in and out as other objects do.
import type { Frame, Point, ShapeObject, TacticsObject, ZoneObject } from "./model.ts";
import { lerp } from "./motion.ts";
import { blendZones, zoneOfShape } from "./zone.ts";

type Area = ZoneObject | ShapeObject;

export const isArea = (item: TacticsObject): item is Area => item.type === "zone" || item.type === "rect" || item.type === "ellipse";

/** The area as a zone about its own middle, turned as it lies: corners and bends with its turn in them, its own turn none. */
function flatZone(item: Area): ZoneObject {
  const zone = item.type === "zone" ? item : zoneOfShape(item);
  const turn = (zone.rotation * Math.PI) / 180, cos = Math.cos(turn), sin = Math.sin(turn);
  const turned = (point: Point) => ({ x: point.x * cos - point.y * sin, y: point.x * sin + point.y * cos });
  const points: number[] = [];
  for (let index = 0; index + 1 < zone.points.length; index += 2) {
    const point = turned({ x: zone.points[index], y: zone.points[index + 1] });
    points.push(point.x, point.y);
  }
  return { ...zone, rotation: 0, points, bends: zone.bends?.map(bend => (bend ? turned(bend) : null)) };
}

/** The areas of `from` gone from `to`: what an area new in `to` can be formed out of. */
export function areasGone(from: Frame, to: Frame): Area[] {
  const after = new Set(to.objects.map(item => item.id));
  return from.objects.filter((item): item is Area => isArea(item) && !item.hidden && !after.has(item.id));
}

/** The areas new in `to` formed out of one gone from `from`: by the new one's id, the one it comes out of; each gone one taken once. */
export function pairAreas(from: Frame, to: Frame): Map<string, Area> {
  const before = new Set(from.objects.map(item => item.id));
  const gone = new Map(areasGone(from, to).map(item => [item.id, item]));
  const result = new Map<string, Area>();
  const taken = new Set<string>();
  for (const item of to.objects) {
    if (!isArea(item) || item.hidden || before.has(item.id) || !item.morphFrom) continue;
    const source = gone.get(item.morphFrom);
    if (!source || taken.has(source.id)) continue;
    taken.add(source.id);
    result.set(item.id, source);
  }
  return result;
}

/** An area part of the way (t, eased, 0 to 1) into the one it turns into: drawn as a zone with the new one's id and look. */
export function morphArea(from: Area, to: Area, t: number): ZoneObject {
  const a = flatZone(from), b = flatZone(to);
  return { ...b, x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t), ...blendZones(a, b, t) };
}
