// From the pitch (metres) to the screen and back: which part of the pitch a
// view shows, and how it fits a frame of a given size. A tall frame turns the
// pitch a quarter so it runs bottom to top, as on a phone held upright: the
// own goal at the foot, attacking upwards.
import { PITCH_LENGTH, PITCH_WIDTH, type PitchView, type Point, type Surroundings } from "./model.ts";

export type Rect = { x: number; y: number; width: number; height: number };

/** Grass around the lines, so objects by the touchline stay reachable. */
export const MARGIN = 4;

/** How much is shown round the lines: more where stands or a fence are drawn round the pitch. */
export const marginFor = (surroundings: Surroundings | undefined) => (surroundings === "arena" ? 14 : surroundings === "training" ? 7 : MARGIN);

export function viewRect(view: PitchView, margin = MARGIN): Rect {
  const half = PITCH_LENGTH / 2;
  switch (view) {
    case "attack": return { x: half - margin, y: -margin, width: half + margin * 2, height: PITCH_WIDTH + margin * 2 };
    case "defend": return { x: -margin, y: -margin, width: half + margin * 2, height: PITCH_WIDTH + margin * 2 };
    default: return { x: -margin, y: -margin, width: PITCH_LENGTH + margin * 2, height: PITCH_WIDTH + margin * 2 };
  }
}

/** The smallest crop, in metres a side: a few players and their moves. */
export const MIN_CROP = 6;

/** What a board shows: its crop where it has one and it is wanted (presenting, links, exports), else its view. */
export function shownRect(board: { view: PitchView; crop?: Rect | null }, margin: number, cropped: boolean): Rect {
  return cropped && board.crop ? board.crop : viewRect(board.view, margin);
}

/** The crop spanned by two corners, never smaller than MIN_CROP a side; null when barely dragged. */
export function cropBetween(a: Point, b: Point): Rect | null {
  const width = Math.abs(b.x - a.x), height = Math.abs(b.y - a.y);
  if (width < 1 && height < 1) return null;
  const w = Math.max(width, MIN_CROP), h = Math.max(height, MIN_CROP);
  const x = Math.min(a.x, b.x) - (w - width) / 2, y = Math.min(a.y, b.y) - (h - height) / 2;
  const round = (value: number) => Math.round(value * 10) / 10;
  return { x: round(x), y: round(y), width: round(w), height: round(h) };
}

/** The pitch group's place, scale and turn that fit the view in the frame. */
export type Fit = { x: number; y: number; scale: number; rotation: 0 | -90 };

/**
 * portrait: a wide view always turned upright (a phone held upright, however little room is left under its bars).
 * upright: never turned (a crop, shown as it was chosen).
 */
export function fitView(rect: Rect, frameWidth: number, frameHeight: number, portrait = false, upright = false): Fit {
  if (frameWidth <= 0 || frameHeight <= 0) return { x: 0, y: 0, scale: 1, rotation: 0 };
  // Turn when the frame is tall and the view is wide (or the other way round).
  const turn = !upright && (portrait ? rect.width > rect.height : frameHeight > frameWidth !== rect.height > rect.width);
  const width = turn ? rect.height : rect.width;
  const height = turn ? rect.width : rect.height;
  const scale = Math.min(frameWidth / width, frameHeight / height);
  const left = (frameWidth - width * scale) / 2;
  const top = (frameHeight - height * scale) / 2;
  if (!turn) return { x: left - rect.x * scale, y: top - rect.y * scale, scale, rotation: 0 };
  // Turned a quarter anticlockwise: a point (x, y) lands at (y, -x).
  return { x: left - rect.y * scale, y: top + (rect.x + rect.width) * scale, scale, rotation: -90 };
}

/**
 * A text's turn on the pitch. A text lies as it did where it was written and
 * turns with the pitch from there. Texts made before kept their turn on the
 * screen; most were written on a wide screen, so that view is taken as where.
 */
export function textTurn(item: { rotation: number; onPitch?: boolean }, board: { view: PitchView; surroundings?: Surroundings }): number {
  if (item.onPitch) return item.rotation;
  return item.rotation - fitView(viewRect(board.view, marginFor(board.surroundings)), 16, 9).rotation;
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
