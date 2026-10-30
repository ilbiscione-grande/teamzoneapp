// 3D: the pitch tilted as if seen from the stand. The ground (the board's
// own stage) is tilted by the browser with TILT; what stands up on it
// (players, the ball, equipment, stands, masts) is drawn upright on a stage
// over it, each point put where the tilted ground shows it by the same sum.
// "Stage" points are the flat board's pixels, as the editor draws them.
import { pitchToFrame, type Fit, type Viewport } from "./geometry.ts";
import type { Point } from "./model.ts";

/** How the ground is tilted: degrees back, the scale, where it turns (a share of the height) and the viewer's distance in pixels. */
export const TILT = { degrees: 52, scale: 0.86, originY: 0.7, perspective: 1150 };

/** The CSS transform that tilts the ground; the parent holds the perspective. */
export const tiltTransform = `rotateX(${TILT.degrees}deg) scale(${TILT.scale})`;
export const tiltOrigin = `50% ${TILT.originY * 100}%`;

/** A point on the screen, and how much nearer (above 1) or farther (below 1) it is than the turning line. */
export type Projected = { x: number; y: number; depth: number };

/** A flat-board point `lift` pixels up off the ground, as the tilted view shows it in a frame of this size. */
export function projectStage(at: Point, lift: number, width: number, height: number): Projected {
  const originX = width / 2, originY = height * TILT.originY;
  const x = (at.x - originX) * TILT.scale, y = (at.y - originY) * TILT.scale, z = lift * TILT.scale;
  const turn = (TILT.degrees * Math.PI) / 180;
  const turnedY = y * Math.cos(turn) - z * Math.sin(turn);
  const turnedZ = y * Math.sin(turn) + z * Math.cos(turn);
  const depth = TILT.perspective / (TILT.perspective - turnedZ);
  const centreX = width / 2, centreY = height / 2;
  return { x: centreX + (originX + x - centreX) * depth, y: centreY + (originY + turnedY - centreY) * depth, depth };
}

/** From the pitch in metres to the tilted screen: through the board's fit and zoom, `lift` metres up. */
export type Projector = {
  (point: Point, lift?: number): Projected;
  /** Pixels per metre where the pitch meets the turning line, before depth. */
  metre: number;
};

export function projector(fit: Fit, sight: Viewport, width: number, height: number): Projector {
  const metre = fit.scale * sight.scale;
  const project = ((point: Point, lift = 0) => {
    const flat = pitchToFrame(point, fit);
    return projectStage({ x: sight.x + flat.x * sight.scale, y: sight.y + flat.y * sight.scale }, lift * metre, width, height);
  }) as Projector;
  project.metre = metre;
  return project;
}

/** The flat-board point the tilted ground shows at this screen point (the inverse of projectStage at lift 0). */
export function unproject(at: Point, width: number, height: number): Point {
  const originX = width / 2, originY = height * TILT.originY, centreY = height / 2;
  const turn = (TILT.degrees * Math.PI) / 180, P = TILT.perspective;
  // Above the horizon nothing of the ground shows; the point just below it stands in.
  const below = Math.max(P * Math.cos(turn) * 0.05, P * Math.cos(turn) + (at.y - centreY) * Math.sin(turn));
  const y = (P * (at.y - originY)) / below;
  const depth = P / (P - y * Math.sin(turn));
  return { x: originX + (at.x - width / 2) / depth / TILT.scale, y: originY + y / TILT.scale };
}

export type Reach = { left: number; top: number; right: number; bottom: number };

/** Steps the reach grows in, so zooming does not make a new canvas at every step. */
const STEP = 64;

/**
 * How far past each side of the frame the tilted ground's own canvas must
 * reach for the ground to fill the frame: its far side shows narrower and
 * lower than the frame, so a canvas the frame's size leaves the edges bare.
 * No further than what is drawn on it reaches (content, in the canvas's
 * pixels), so a zoomed-out pitch keeps a small canvas.
 */
export function groundReach(width: number, height: number, content?: { x: number; y: number; width: number; height: number }): Reach {
  const corners = [{ x: 0, y: 0 }, { x: width, y: 0 }, { x: 0, y: height }, { x: width, y: height }].map(at => unproject(at, width, height));
  const xs = corners.map(point => point.x), ys = corners.map(point => point.y);
  const beyond = content
    ? { left: -content.x, top: -content.y, right: content.x + content.width - width, bottom: content.y + content.height - height }
    : { left: Infinity, top: Infinity, right: Infinity, bottom: Infinity };
  const limit = (needed: number, drawn: number, most: number) => Math.ceil(Math.min(most, Math.max(0, needed), Math.max(0, drawn)) / STEP) * STEP;
  return {
    left: limit(-Math.min(...xs), beyond.left, width), right: limit(Math.max(...xs) - width, beyond.right, width),
    top: limit(-Math.min(...ys), beyond.top, height * 2), bottom: limit(Math.max(...ys) - height, beyond.bottom, height),
  };
}
