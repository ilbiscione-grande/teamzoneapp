// From the pitch (metres) to the screen and back: which part of the pitch a
// view shows, and how it fits a frame of a given size. A tall frame turns the
// pitch a quarter so it runs bottom to top, as on a phone held upright: the
// own goal at the foot, attacking upwards.
import { PITCH_LENGTH, PITCH_WIDTH, type PitchView, type Point, type Surroundings } from "./model.ts";

export type Rect = { x: number; y: number; width: number; height: number };

/** Grass around the lines, so objects by the touchline stay reachable. */
export const MARGIN = 4;

/** How much is shown round the lines: more where stands or a fence are drawn round the pitch. */
export const marginFor = (surroundings: Surroundings | undefined) => (surroundings === "arena" ? 11 : surroundings === "training" ? 7 : MARGIN);

export function viewRect(view: PitchView, margin = MARGIN): Rect {
  const half = PITCH_LENGTH / 2;
  switch (view) {
    case "attack": return { x: half - margin, y: -margin, width: half + margin * 2, height: PITCH_WIDTH + margin * 2 };
    case "defend": return { x: -margin, y: -margin, width: half + margin * 2, height: PITCH_WIDTH + margin * 2 };
    default: return { x: -margin, y: -margin, width: PITCH_LENGTH + margin * 2, height: PITCH_WIDTH + margin * 2 };
  }
}

/** The pitch group's place, scale and turn that fit the view in the frame. */
export type Fit = { x: number; y: number; scale: number; rotation: 0 | -90 };

export function fitView(rect: Rect, frameWidth: number, frameHeight: number): Fit {
  if (frameWidth <= 0 || frameHeight <= 0) return { x: 0, y: 0, scale: 1, rotation: 0 };
  // Turn when the frame is tall and the view is wide (or the other way round).
  const turn = frameHeight > frameWidth !== rect.height > rect.width;
  const width = turn ? rect.height : rect.width;
  const height = turn ? rect.width : rect.height;
  const scale = Math.min(frameWidth / width, frameHeight / height);
  const left = (frameWidth - width * scale) / 2;
  const top = (frameHeight - height * scale) / 2;
  if (!turn) return { x: left - rect.x * scale, y: top - rect.y * scale, scale, rotation: 0 };
  // Turned a quarter anticlockwise: a point (x, y) lands at (y, -x).
  return { x: left - rect.y * scale, y: top + (rect.x + rect.width) * scale, scale, rotation: -90 };
}

/** A pitch point on the screen, before the user's zoom and pan. */
export function pitchToFrame(point: Point, fit: Fit): Point {
  if (fit.rotation === 0) return { x: fit.x + point.x * fit.scale, y: fit.y + point.y * fit.scale };
  return { x: fit.x + point.y * fit.scale, y: fit.y - point.x * fit.scale };
}

export const clamp = (value: number, min: number, max: number) => Math.min(max, Math.max(min, value));

export type Viewport = { x: number; y: number; scale: number };

export const MIN_ZOOM = 0.6;
export const MAX_ZOOM = 4;

/** Zooms by a factor around a point on the screen, keeping it in place. */
export function zoomAround(viewport: Viewport, factor: number, center: Point): Viewport {
  const scale = clamp(viewport.scale * factor, MIN_ZOOM, MAX_ZOOM);
  const ratio = scale / viewport.scale;
  return { scale, x: center.x - (center.x - viewport.x) * ratio, y: center.y - (center.y - viewport.y) * ratio };
}

/**
 * The view `scale` times in with a pitch point in the middle of a frame of
 * this size, as near the middle as it can be without showing more than the
 * whole view does (an object at the touchline is not shown half off it).
 */
export function zoomTo(point: Point, fit: Fit, width: number, height: number, scale: number): Viewport {
  const at = pitchToFrame(point, fit);
  return {
    scale,
    x: clamp(width / 2 - at.x * scale, width - width * scale, 0),
    y: clamp(height / 2 - at.y * scale, height - height * scale, 0),
  };
}

/** Part of the way (0–1) from one view to another. */
export function blendViewport(from: Viewport, to: Viewport, amount: number): Viewport {
  const part = (a: number, b: number) => a + (b - a) * amount;
  return { x: part(from.x, to.x), y: part(from.y, to.y), scale: part(from.scale, to.scale) };
}

export const distance = (a: Point, b: Point) => Math.hypot(a.x - b.x, a.y - b.y);
export const midpoint = (a: Point, b: Point): Point => ({ x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 });
