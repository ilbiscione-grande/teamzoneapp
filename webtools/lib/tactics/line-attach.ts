// An arrow's start sticks to a player, as the ball does: drawn from a
// player, or its start dragged onto one. It then starts at the player's
// ring, on the side it goes, and follows the player when the player moves;
// the end and the bend stay where they are. Dragged away, it comes loose.
import { PLAYER_RADIUS } from "./ball.ts";
import type { LineObject, PlayerObject, Point, TacticsObject } from "./model.ts";

/** How near a player's middle an arrow's start must be to stick: on the player or just off it. */
export const LINE_SNAP = PLAYER_RADIUS + 0.8;

/** The nearest visible player the point is on, or null. */
export function playerAt(point: Point, objects: TacticsObject[]): PlayerObject | null {
  let best: PlayerObject | null = null;
  let bestGap = LINE_SNAP;
  for (const item of objects) {
    if (item.type !== "player" || item.hidden) continue;
    const gap = Math.hypot(point.x - item.x, point.y - item.y);
    if (gap <= bestGap) { best = item; bestGap = gap; }
  }
  return best;
}

/** The line starting on the player's ring, facing its bend or end, which stay where they are. */
export function startAt(line: LineObject, player: Point): LineObject {
  const end = { x: line.x + line.points[2], y: line.y + line.points[3] };
  const bend = line.control ? { x: line.x + line.control.x, y: line.y + line.control.y } : null;
  const toward = bend ?? end;
  const dx = toward.x - player.x, dy = toward.y - player.y;
  const length = Math.hypot(dx, dy);
  const start = length < 0.001 ? { x: player.x, y: player.y } : { x: player.x + (dx / length) * PLAYER_RADIUS, y: player.y + (dy / length) * PLAYER_RADIUS };
  return {
    ...line, x: start.x, y: start.y, points: [0, 0, end.x - start.x, end.y - start.y],
    control: bend ? { x: bend.x - start.x, y: bend.y - start.y } : null,
  };
}

/** The line stuck to the player its start is on, or loose. A line without a head stays loose. */
export function attachLine(line: LineObject, objects: TacticsObject[]): LineObject {
  const player = line.arrow === "none" ? null : playerAt({ x: line.x + line.points[0], y: line.y + line.points[1] }, objects);
  return player ? startAt({ ...line, from: player.id }, player) : line.from ? { ...line, from: null } : line;
}

const near = (a: number, b: number) => Math.abs(a - b) < 1e-9;

/** Lines follow the players their start is on; a removed player lets go. */
export function settleLines(objects: TacticsObject[]): TacticsObject[] {
  if (!objects.some(item => item.type === "line" && item.from)) return objects;
  const players = new Map(objects.filter((item): item is PlayerObject => item.type === "player").map(item => [item.id, item]));
  return objects.map(item => {
    if (item.type !== "line" || !item.from) return item;
    const player = players.get(item.from);
    if (!player) return { ...item, from: null };
    const placed = startAt(item, player);
    const same = near(placed.x, item.x) && near(placed.y, item.y) && placed.points.every((value, index) => near(value, item.points[index]));
    return same ? item : placed;
  });
}
