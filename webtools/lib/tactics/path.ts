// Lines as point lists: a curved line sampled into short steps, and a line
// cut to a share of its length (for drawing it out while it plays).
import type { Point } from "./model.ts";
import { curvePoint } from "./motion.ts";

/** A curve through `through` at its middle, as points: the drawn curve of a bent line or path. */
export function sampleCurve(from: Point, to: Point, through: Point | null, steps = 24): number[] {
  if (!through) return [from.x, from.y, to.x, to.y];
  // The control that makes the curve pass through the point halfway.
  const control = { x: 2 * through.x - (from.x + to.x) / 2, y: 2 * through.y - (from.y + to.y) / 2 };
  const points: number[] = [];
  for (let i = 0; i <= steps; i++) {
    const at = curvePoint(from, to, control, i / steps);
    points.push(at.x, at.y);
  }
  return points;
}

/** The control point for a curve that passes through `through` halfway. */
export function controlThrough(from: Point, to: Point, through: Point): Point {
  return { x: 2 * through.x - (from.x + to.x) / 2, y: 2 * through.y - (from.y + to.y) / 2 };
}

/** The point halfway along a curve with this control (or the middle of the straight line). */
export function curveMiddle(from: Point, to: Point, control: Point | null | undefined): Point {
  return curvePoint(from, to, control, 0.5);
}

/** The first `share` (0–1) of a polyline, by length. */
export function partialPolyline(points: number[], share: number): number[] {
  if (share >= 1 || points.length < 4) return points;
  const lengths: number[] = [];
  let total = 0;
  for (let i = 2; i < points.length; i += 2) {
    const length = Math.hypot(points[i] - points[i - 2], points[i + 1] - points[i - 1]);
    lengths.push(length);
    total += length;
  }
  let left = Math.max(0, share) * total;
  const result = [points[0], points[1]];
  for (let segment = 0; segment < lengths.length; segment++) {
    const i = (segment + 1) * 2;
    if (left >= lengths[segment]) {
      result.push(points[i], points[i + 1]);
      left -= lengths[segment];
      continue;
    }
    const t = lengths[segment] > 0 ? left / lengths[segment] : 0;
    result.push(points[i - 2] + (points[i] - points[i - 2]) * t, points[i - 1] + (points[i + 1] - points[i - 1]) * t);
    break;
  }
  // Konva needs two points for a line.
  return result.length >= 4 ? result : [...result, result[0], result[1]];
}
