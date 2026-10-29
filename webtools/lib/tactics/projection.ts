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
