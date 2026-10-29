// What a move is made of, shared by playing (timeline.ts) and what is drawn
// along a move (marks.ts): easing, curves and an object's effects.
import type { Easing, Effect, Point, TacticsObject } from "./model.ts";

export const easeInOut = (t: number) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
export const easeOut = (t: number) => 1 - Math.pow(1 - t, 3);

const easings: Record<Easing, (t: number) => number> = {
  smooth: easeInOut,
  linear: t => t,
  in: t => t * t * t,
  out: easeOut,
};

/** Progress t (0–1) of a move as the frame's easing shapes it; smooth when not set. */
export const ease = (easing: Easing | undefined, t: number) => (easings[easing ?? "smooth"] ?? easeInOut)(t);

/** A quick start of a move: done after `share` of it (the arrow drawn out, the zoom in, the ring on). */
export const quick = (t: number, share = 0.3) => easeOut(Math.min(1, Math.max(0, t / share)));

/** An object's effects in its frame: several, or the one of a board from before several could be chosen. */
export function effectsOf(item: TacticsObject): Effect[] {
  if (Array.isArray(item.effects)) return item.effects;
  return item.effect ? [item.effect] : [];
}

export const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
export const lerpPoint = (a: Point, b: Point, t: number): Point => ({ x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t) });

/** Along a curve through the control point (quadratic: the control pulls the path). */
export function curvePoint(from: Point, to: Point, control: Point | null | undefined, t: number): Point {
  if (!control) return lerpPoint(from, to, t);
  const inv = 1 - t;
  return {
    x: inv * inv * from.x + 2 * inv * t * control.x + t * t * to.x,
    y: inv * inv * from.y + 2 * inv * t * control.y + t * t * to.y,
  };
}
