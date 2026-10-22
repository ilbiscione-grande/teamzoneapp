// Playing a board: where the playhead is after some time, and the objects
// between two frames. The playhead counts frames: 2.4 is 40 % of the way
// from frame 2 to frame 3. From the first Tacticsboard, as pure functions.
import { ballPosition } from "./ball.ts";
import type { BallObject, Frame, LineObject, Point, ShapeObject, TacticsObject } from "./model.ts";

/** What playing adds to an object: how visible, how large, how far drawn, how lit. */
export type Rendered = TacticsObject & { opacity?: number; grow?: number; drawn?: number; glow?: number };

/** A move's length in ms: the time into frame `index` (frame 0 has none). */
export const moveTime = (frames: Frame[], index: number) => Math.max(100, frames[index]?.durationMs ?? 1500);

/** The whole play's length at a speed. */
export function totalTime(frames: Frame[], speed = 1): number {
  let total = 0;
  for (let index = 1; index < frames.length; index++) total += moveTime(frames, index);
  return total / speed;
}

/** The playhead after `elapsed` ms, from `from` (a frame index); null when the play is over. */
export function playheadAt(frames: Frame[], elapsed: number, speed = 1, loop = false, from = 0): number | null {
  if (frames.length < 2) return null;
  let time = elapsed * speed;
  let index = Math.max(0, Math.floor(from));
  // Starting part-way through a move.
  time += (from - index) * moveTime(frames, index + 1);
  for (;;) {
    if (index >= frames.length - 1) {
      if (!loop) return null;
      index = 0;
    }
    const length = moveTime(frames, index + 1);
    if (time < length) return index + time / length;
    time -= length;
    index++;
  }
}

export const easeInOut = (t: number) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
const lerpPoint = (a: Point, b: Point, t: number): Point => ({ x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t) });

/** Along a curve through the control point (quadratic: the control pulls the path). */
export function curvePoint(from: Point, to: Point, control: Point | null | undefined, t: number): Point {
  if (!control) return lerpPoint(from, to, t);
  const inv = 1 - t;
  return {
    x: inv * inv * from.x + 2 * inv * t * control.x + t * t * to.x,
    y: inv * inv * from.y + 2 * inv * t * control.y + t * t * to.y,
  };
}

/** The shortest turn between two angles. */
const lerpAngle = (a: number, b: number, t: number) => {
  const delta = ((((b - a) % 360) + 540) % 360) - 180;
  return a + delta * t;
};

/** An effect's look at progress t (0–1) of the move into the frame. */
function withEffect(item: TacticsObject, t: number, entering: boolean): Rendered {
  switch (item.effect) {
    case "pop": {
      // Grows past full size and settles.
      const grow = t < 0.6 ? lerp(0.2, 1.25, t / 0.6) : lerp(1.25, 1, (t - 0.6) / 0.4);
      return { ...item, grow, opacity: Math.min(1, t * 3) };
    }
    case "draw":
      return { ...item, drawn: t, opacity: entering ? Math.min(1, t * 4) : 1 };
    case "pulse":
      return { ...item, grow: 1 + Math.sin(t * Math.PI * 3) * 0.14 * (1 - t * 0.5) };
    case "highlight":
      return { ...item, glow: Math.sin(t * Math.PI) * 0.6 + t * 0.4, opacity: entering ? t : 1 };
    default:
      return entering ? { ...item, opacity: t } : item;
  }
}

/** The objects at progress t (0–1) of the move from one frame to the next. */
export function blendFrames(from: Frame, to: Frame, t: number): Rendered[] {
  const eased = easeInOut(t);
  const before = new Map(from.objects.map(item => [item.id, item]));
  const after = new Map(to.objects.map(item => [item.id, item]));
  const result: Rendered[] = [];

  for (const next of to.objects) {
    const prev = before.get(next.id);
    if (!prev) {
      // New in this frame: in by its effect, fading by default.
      result.push(withEffect(next, t, true));
      continue;
    }
    let blended: TacticsObject = {
      ...next,
      ...curvePoint(prev, next, next.pathControl, eased),
      rotation: lerpAngle(prev.rotation, next.rotation, eased),
    };
    if (next.type === "line" && prev.type === "line") {
      const points = prev.points.map((value, i) => lerp(value, next.points[i], eased)) as LineObject["points"];
      const control = prev.control && next.control ? lerpPoint(prev.control, next.control, eased) : next.control;
      blended = { ...blended, points, control } as LineObject;
    }
    if (next.type === "freehand" && prev.type === "freehand" && next.points.length === prev.points.length) {
      blended = { ...blended, points: prev.points.map((value, i) => lerp(value, next.points[i], eased)) } as TacticsObject;
    }
    if ((next.type === "rect" || next.type === "ellipse") && prev.type === next.type) {
      const shape = prev as ShapeObject;
      blended = { ...blended, width: lerp(shape.width, next.width, eased), height: lerp(shape.height, next.height, eased) } as ShapeObject;
    }
    if ("scale" in next && "scale" in prev) blended = { ...blended, scale: lerp(prev.scale, next.scale, eased) } as TacticsObject;
    result.push(withEffect(blended, t, false));
  }
  // Gone in the next frame: fades out where it was.
  for (const prev of from.objects) {
    if (!after.has(prev.id)) result.push({ ...prev, opacity: 1 - t });
  }

  // Balls: held by the same player in both frames, the ball rides with them;
  // otherwise it travels from where it lay to where it lies (a pass).
  const playersNow = result;
  return result.map(item => {
    if (item.type !== "ball") return item;
    const prev = before.get(item.id) as BallObject | undefined;
    const next = after.get(item.id) as BallObject | undefined;
    if (!prev || !next) return item;
    if (prev.attachedTo && prev.attachedTo === next.attachedTo && prev.offset && next.offset) {
      const holder = playersNow.find(other => other.id === next.attachedTo);
      if (holder) {
        const offset = lerpPoint(prev.offset, next.offset, eased);
        return { ...item, x: holder.x + offset.x, y: holder.y + offset.y };
      }
    }
    const start = ballPosition(prev, from.objects);
    const end = ballPosition(next, to.objects);
    return { ...item, ...curvePoint(start, end, next.pathControl, eased) };
  });
}

/** What the board shows at a playhead: a frame, or a move between two. */
export function objectsAt(frames: Frame[], playhead: number): Rendered[] {
  if (frames.length === 0) return [];
  const index = Math.min(frames.length - 1, Math.max(0, Math.floor(playhead)));
  const t = playhead - index;
  if (index >= frames.length - 1 || t <= 0) return frames[index].objects;
  return blendFrames(frames[index], frames[index + 1], t);
}
