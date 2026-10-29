// Playing a board: where the playhead is after some time, and the objects
// between two frames. The playhead counts frames: 2.4 is 40 % of the way
// from frame 2 to frame 3. From the first Tacticsboard, as pure functions.
// What is drawn along a move (trails, arrows, rings, the zoom) is in marks.ts.
import { ballPosition } from "./ball.ts";
import { withMarks, type Marks } from "./marks.ts";
import type { BallObject, Effect, Frame, LineObject, ShapeObject, TacticsObject } from "./model.ts";
import { curvePoint, ease, effectsOf, lerp, lerpPoint } from "./motion.ts";

export { curvePoint, ease, easeInOut, effectsOf } from "./motion.ts";
export type { Trail } from "./marks.ts";

/** What playing adds to an object: how visible, how large, how far drawn, how lit, and the marks along its move. */
export type Rendered = TacticsObject & Marks & { opacity?: number; grow?: number; drawn?: number; glow?: number };

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

/** The shortest turn between two angles. */
const lerpAngle = (a: number, b: number, t: number) => {
  const delta = ((((b - a) % 360) + 540) % 360) - 180;
  return a + delta * t;
};

type Look = { opacity?: number; grow?: number; drawn?: number; glow?: number };

/** Effects drawn along the move or on the view (marks.ts), not on the object. */
const MARKS = new Set<Effect>(["trail", "arrow", "ring", "zoom"]);

/** One effect's look at progress t (0–1) of the move into the frame. */
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
    case "fade":
      return entering ? { opacity: t } : {};
    default:
      return {};
  }
}

/** The effects' looks together: the faintest opacity, the sizes multiplied, the least drawn, the brightest glow. */
function withEffects(item: TacticsObject, t: number, entering: boolean): Rendered {
  const chosen = effectsOf(item);
  // Without a way in of its own, a new object fades in.
  const kinds: Effect[] = chosen.some(kind => !MARKS.has(kind)) ? chosen : ["fade", ...chosen];
  const result: Rendered = { ...item };
  for (const look of kinds.map(kind => effectLook(kind, t, entering))) {
    if (look.opacity !== undefined) result.opacity = Math.min(result.opacity ?? 1, look.opacity);
    if (look.grow !== undefined) result.grow = (result.grow ?? 1) * look.grow;
    if (look.drawn !== undefined) result.drawn = Math.min(result.drawn ?? 1, look.drawn);
    if (look.glow !== undefined) result.glow = Math.max(result.glow ?? 0, look.glow);
  }
  return result;
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
    result.push(withEffects(blended, t, false));
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

/** What the board shows at a playhead: a frame, or a move between two, with the marks along it. */
export function objectsAt(frames: Frame[], playhead: number): Rendered[] {
  if (frames.length === 0) return [];
  const index = Math.min(frames.length - 1, Math.max(0, Math.floor(playhead)));
  const t = playhead - index;
  const shown: Rendered[] = index >= frames.length - 1 || t <= 0 ? frames[index].objects : blendFrames(frames[index], frames[index + 1], t);
  return withMarks(frames, playhead, shown);
}
