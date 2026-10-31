// Measuring on the pitch, in metres (the pitch is 105 × 68): an area's size
// and how much ground it covers, a line's length, the ruler's distance, and
// a line through players (ChainObject) found from where they stand.
import type { ChainObject, PlayerObject, Point, ShapeObject, TacticsObject } from "./model.ts";

const decimal = (value: number, digits: number) => value.toLocaleString("sv-SE", { maximumFractionDigits: digits, minimumFractionDigits: 0 });

/** Metres as a coach reads them: whole metres from 10, one decimal below. */
export function metres(value: number): string {
  return `${decimal(value, value >= 10 ? 0 : 1)} m`;
}

/** Square metres, rounded to whole ones (to tens from 1 000). */
export function squareMetres(value: number): string {
  const rounded = value >= 1000 ? Math.round(value / 10) * 10 : Math.round(value);
  return `${rounded.toLocaleString("sv-SE")} m²`;
}

export const distance = (a: Point, b: Point) => Math.hypot(b.x - a.x, b.y - a.y);

/** An area's sides and the ground it covers: a rectangle's sides, an ellipse's two diameters. */
export function shapeMeasure(shape: Pick<ShapeObject, "type" | "width" | "height">): string {
  const area = shape.type === "rect" ? shape.width * shape.height : (Math.PI * shape.width * shape.height) / 4;
  const sides = `${decimal(shape.width, shape.width >= 10 ? 0 : 1)} × ${metres(shape.height)}`;
  return `${shape.type === "ellipse" ? "Ø " : ""}${sides} · ${squareMetres(area)}`;
}

/** The ground inside a closed outline (the shoelace formula). */
export function polygonArea(points: Point[]): number {
  let twice = 0;
  for (let index = 0; index < points.length; index++) {
    const a = points[index], b = points[(index + 1) % points.length];
    twice += a.x * b.y - b.x * a.y;
  }
  return Math.abs(twice) / 2;
}

/** An outline's or a path's length; a closed one back to its start. */
export function pathLength(points: Point[], closed: boolean): number {
  let total = 0;
  for (let index = 1; index < points.length; index++) total += distance(points[index - 1], points[index]);
  return closed && points.length > 2 ? total + distance(points[points.length - 1], points[0]) : total;
}

/** The point halfway along a path, where its length is tagged clear of its ends. */
export function halfway(points: Point[]): Point {
  let left = pathLength(points, false) / 2;
  for (let index = 1; index < points.length; index++) {
    const a = points[index - 1], b = points[index], step = distance(a, b);
    if (step >= left && step > 0) return { x: a.x + ((b.x - a.x) * left) / step, y: a.y + ((b.y - a.y) * left) / step };
    left -= step;
  }
  return points[points.length - 1];
}

/** Where a chain's players stand, in its order; players gone from the frame or hidden are left out. */
export function chainPoints(chain: Pick<ChainObject, "players">, objects: TacticsObject[], moved: Record<string, Point> = {}): Point[] {
  const byId = new Map(objects.map(item => [item.id, item]));
  return chain.players.flatMap(id => {
    const player = byId.get(id);
    if (!player || player.type !== "player" || player.hidden) return [];
    return [moved[id] ?? { x: player.x, y: player.y }];
  });
}

/**
 * The players in the order a chain goes through them: closed, round their
 * middle, so the outline never crosses itself; open, in the order they were
 * picked (one by one with shift, or as they lie in the frame).
 */
export function chainOrder(players: PlayerObject[], closed: boolean): string[] {
  if (!closed || players.length < 3) return players.map(item => item.id);
  const middle = { x: players.reduce((sum, item) => sum + item.x, 0) / players.length, y: players.reduce((sum, item) => sum + item.y, 0) / players.length };
  return [...players].sort((a, b) => Math.atan2(a.y - middle.y, a.x - middle.x) - Math.atan2(b.y - middle.y, b.x - middle.x)).map(item => item.id);
}
