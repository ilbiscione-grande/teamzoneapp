// Playing a board: where the playhead is after some time, and the objects
// between two frames. The playhead counts frames: 2.4 is 40 % of the way
// from frame 2 to frame 3. From the first Tacticsboard, as pure functions.
import { ballPosition } from "./ball.ts";
import type { BallObject, Easing, Effect, Frame, LineObject, Point, ShapeObject, TacticsObject } from "./model.ts";

/** A trail behind a moving object: pitch points x, y, … and how visible. */
export type Trail = { points: number[]; opacity: number };

/** What playing adds to an object: how visible, how large, how far drawn, how lit, and the trails behind it. */
export type Rendered = TacticsObject & { opacity?: number; grow?: number; drawn?: number; glow?: number; trails?: Trail[] };

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

const easings: Record<Easing, (t: number) => number> = {
  smooth: easeInOut,
  linear: t => t,
  in: t => t * t * t,
  out: t => 1 - Math.pow(1 - t, 3),
};

/** Progress t (0–1) of a move as the frame's easing shapes it; smooth when not set. */
export const ease = (easing: Easing | undefined, t: number) => (easings[easing ?? "smooth"] ?? easeInOut)(t);

/** An object's effects in its frame: several, or the one of a board from before several could be chosen. */
export function effectsOf(item: TacticsObject): Effect[] {
  if (Array.isArray(item.effects)) return item.effects;
  return item.effect ? [item.effect] : [];
}

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

type Look = { opacity?: number; grow?: number; drawn?: number; glow?: number };

/** One effect's look at progress t (0–1) of the move into the frame. A trail is drawn apart (trailOf). */
function effectLook(effect: Effect, t: number, entering: boolean): Look {
  switch (effect) {
    case "pop":
      // Grows past full size and settles.
      return { grow: t < 0.6 ? lerp(0.2, 1.25, t / 0.6) : lerp(1.25, 1, (t - 0.6) / 0.4), opacity: Math.min(1, t * 3) };
    case "draw":
      return { drawn: t, opacity: entering ? Math.min(1, t * 4) : 1 };
    case "pulse":
      return { grow: 1 + Math.sin(t * Math.PI * 3) * 0.14 * (1 - t * 0.5) };
    case "highlight":
      return { glow: Math.sin(t * Math.PI) * 0.6 + t * 0.4, opacity: entering ? t : 1 };
    case "trail":
      return {};
    default:
      return entering ? { opacity: t } : {};
  }
}

/** The effects' looks together: the faintest opacity, the sizes multiplied, the least drawn, the brightest glow. */
function withEffects(item: TacticsObject, t: number, entering: boolean): Rendered {
  const chosen = effectsOf(item);
  // Without a way in of its own, a new object fades in.
  const kinds: Effect[] = chosen.some(kind => kind !== "trail") ? chosen : ["fade", ...chosen];
  const result: Rendered = { ...item };
  for (const look of kinds.map(kind => effectLook(kind, t, entering))) {
    if (look.opacity !== undefined) result.opacity = Math.min(result.opacity ?? 1, look.opacity);
    if (look.grow !== undefined) result.grow = (result.grow ?? 1) * look.grow;
    if (look.drawn !== undefined) result.drawn = Math.min(result.drawn ?? 1, look.drawn);
    if (look.glow !== undefined) result.glow = Math.max(result.glow ?? 0, look.glow);
  }
  return result;
}

const TRAIL_STEPS = 24;
/** Shorter moves leave no trail. */
const TRAIL_MIN = 0.3;

/**
 * The trail an object with the trail effect leaves on its move from one
 * frame to the next, up to progress `upTo` (eased), as pitch points x, y, …;
 * null without the effect, without a move, or for a ball riding with its
 * holder.
 */
export function trailOf(from: Frame, to: Frame, id: string, upTo: number): number[] | null {
  const next = to.objects.find(item => item.id === id);
  const prev = from.objects.find(item => item.id === id);
  if (!next || !prev || !effectsOf(next).includes("trail")) return null;
  let start: Point = prev;
  let end: Point = next;
  if (next.type === "ball" && prev.type === "ball") {
    if (prev.attachedTo && prev.attachedTo === next.attachedTo) return null;
    start = ballPosition(prev, from.objects);
    end = ballPosition(next, to.objects);
  }
  if (Math.hypot(end.x - start.x, end.y - start.y) < TRAIL_MIN || upTo <= 0) return null;
  const points: number[] = [];
  for (let i = 0; i <= TRAIL_STEPS; i++) {
    const at = curvePoint(start, end, next.pathControl, (upTo * i) / TRAIL_STEPS);
    points.push(at.x, at.y);
  }
  return points;
}

/** The objects at progress t (0–1) of the move from one frame to the next. */
export function blendFrames(from: Frame, to: Frame, t: number): Rendered[] {
  const eased = ease(to.easing, t);
  const before = new Map(from.objects.map(item => [item.id, item]));
  const after = new Map(to.objects.map(item => [item.id, item]));
  const result: Rendered[] = [];

  for (const next of to.objects) {
    const prev = before.get(next.id);
    if (!prev) {
      // New in this frame: in by its effects, fading by default.
      result.push(withEffects(next, t, true));
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
    const rendered = withEffects(blended, t, false);
    const trail = trailOf(from, to, next.id, eased);
    result.push(trail ? { ...rendered, trails: [{ points: trail, opacity: 1 }] } : rendered);
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

/** Adds the trails left on the move into frame `index`, fading by `opacity`, to the objects still there. */
function withEarlierTrails(frames: Frame[], index: number, objects: Rendered[], opacity: number): Rendered[] {
  if (index < 1 || opacity <= 0) return objects;
  return objects.map(item => {
    const points = trailOf(frames[index - 1], frames[index], item.id, 1);
    return points ? { ...item, trails: [{ points, opacity }, ...(item.trails ?? [])] } : item;
  });
}

/**
 * What the board shows at a playhead: a frame, or a move between two. A
 * trail stays drawn on reaching its frame and fades out over the next move.
 */
export function objectsAt(frames: Frame[], playhead: number): Rendered[] {
  if (frames.length === 0) return [];
  const index = Math.min(frames.length - 1, Math.max(0, Math.floor(playhead)));
  const t = playhead - index;
  if (index >= frames.length - 1 || t <= 0) return withEarlierTrails(frames, index, frames[index].objects, 1);
  return withEarlierTrails(frames, index, blendFrames(frames[index], frames[index + 1], t), 1 - t);
}
