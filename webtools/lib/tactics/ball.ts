// The ball sticks to a player where it is dropped: dropped near a player it
// lies on the player's edge in the direction it was dropped from, and keeps
// that place as the player moves. From the first Tacticsboard.
import type { BallObject, PlayerObject, Point, TacticsObject } from "./model.ts";

export const PLAYER_RADIUS = 1.6;
export const BALL_RADIUS = 0.85;
/** The ball touches the player's ring, with a little overlap. */
export const ATTACH_DISTANCE = PLAYER_RADIUS + BALL_RADIUS - 0.3;
/** How near the player the ball must be dropped to stick. */
export const SNAP_RADIUS = PLAYER_RADIUS + 3;

/** The nearest visible player within reach of the drop, or null. */
export function nearestPlayer(position: Point, objects: TacticsObject[]): PlayerObject | null {
  let best: PlayerObject | null = null;
  let bestDistance = Infinity;
  for (const item of objects) {
    if (item.type !== "player" || item.hidden) continue;
    const gap = Math.hypot(position.x - item.x, position.y - item.y);
    if (gap < bestDistance) {
      best = item;
      bestDistance = gap;
    }
  }
  return best && bestDistance <= SNAP_RADIUS ? best : null;
}

/** The offset on the player's edge pointing at where the ball was dropped. */
export function edgeOffset(player: Point, dropped: Point): Point {
  const dx = dropped.x - player.x;
  const dy = dropped.y - player.y;
  const length = Math.hypot(dx, dy);
  // Dropped dead centre: up and to the right.
  if (length < 0.001) return { x: ATTACH_DISTANCE / Math.SQRT2, y: -ATTACH_DISTANCE / Math.SQRT2 };
  return { x: (dx / length) * ATTACH_DISTANCE, y: (dy / length) * ATTACH_DISTANCE };
}

/** The ball after being dropped at a position: stuck to a player or loose. */
export function dropBall(ball: BallObject, position: Point, objects: TacticsObject[], attach = true): BallObject {
  const player = attach ? nearestPlayer(position, objects) : null;
  if (!player) return { ...ball, x: position.x, y: position.y, attachedTo: null, offset: null };
  const offset = edgeOffset(player, position);
  return { ...ball, x: player.x + offset.x, y: player.y + offset.y, attachedTo: player.id, offset };
}

/** Where an attached ball lies for its player, or its own place. */
export function ballPosition(ball: BallObject, objects: TacticsObject[]): Point {
  if (!ball.attachedTo || !ball.offset) return { x: ball.x, y: ball.y };
  const player = objects.find(item => item.id === ball.attachedTo && item.type === "player");
  return player ? { x: player.x + ball.offset.x, y: player.y + ball.offset.y } : { x: ball.x, y: ball.y };
}

/** Balls follow players that moved; balls of removed players come loose. */
export function settleBalls(objects: TacticsObject[]): TacticsObject[] {
  return objects.map(item => {
    if (item.type !== "ball" || !item.attachedTo) return item;
    const player = objects.find(other => other.id === item.attachedTo && other.type === "player");
    if (!player) return { ...item, attachedTo: null, offset: null };
    const position = ballPosition(item, objects);
    return position.x === item.x && position.y === item.y ? item : { ...item, ...position };
  });
}

/**
 * The players holding a ball: it is attached to them and lies at their
 * feet. A ball on its way in a pass is attached already but not yet there.
 */
export function ballHolders(objects: TacticsObject[]): Set<string> {
  const players = new Map(objects.filter(item => item.type === "player").map(item => [item.id, item]));
  const holders = new Set<string>();
  for (const item of objects) {
    if (item.type !== "ball" || item.hidden || !item.attachedTo) continue;
    const player = players.get(item.attachedTo);
    if (player && !player.hidden && Math.hypot(player.x - item.x, player.y - item.y) <= PLAYER_RADIUS + BALL_RADIUS + 0.5) holders.add(player.id);
  }
  return holders;
}
