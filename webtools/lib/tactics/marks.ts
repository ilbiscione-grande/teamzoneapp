// What some effects draw along a move rather than on the object itself: a
// trail behind it ("trail"), an arrow ahead of it ("arrow"), a ring round it
// ("ring"), and the view zooming in on it ("zoom"). Each is played while
// the board moves into the frame that has it; a trail and a ring stay on
// reaching the frame and fade out over the next move.
import { ballPosition } from "./ball.ts";
import type { Frame, Point, TacticsObject } from "./model.ts";
import { curvePoint, ease, effectsOf, lerp, lerpPoint, quick } from "./motion.ts";

/** A dashed track along a move: pitch points x, y, …, how visible, and whether it ends in an arrowhead. */
export type Trail = { points: number[]; opacity: number; arrow?: boolean };
/** A ring round an object: how visible, and how large (1 when settled). */
export type Ring = { opacity: number; grow: number };
/** What the marks add to an object while the board plays. */
export type Marks = { trails?: Trail[]; ring?: Ring };

const STEPS = 24;
/** Shorter moves leave no trail or arrow. */
const MIN_MOVE = 0.3;
/** How close the view comes: this many times the whole view. */
export const ZOOM = 2.2;

type Path = { start: Point; end: Point; control: Point | null | undefined };

/** An object's way from one frame to the next; null when it is new, gone, still or a ball riding with its holder. */
function pathOf(from: Frame, to: Frame, id: string): Path | null {
  const next = to.objects.find(item => item.id === id);
  const prev = from.objects.find(item => item.id === id);
  if (!next || !prev) return null;
  let start: Point = prev;
  let end: Point = next;
  if (next.type === "ball" && prev.type === "ball") {
    if (prev.attachedTo && prev.attachedTo === next.attachedTo) return null;
    start = ballPosition(prev, from.objects);
    end = ballPosition(next, to.objects);
  }
  if (Math.hypot(end.x - start.x, end.y - start.y) < MIN_MOVE) return null;
  return { start, end, control: next.pathControl };
}

/** The path from progress `from` to `to` (0–1) as pitch points. */
function sample(path: Path, from: number, to: number): number[] {
  const points: number[] = [];
  for (let i = 0; i <= STEPS; i++) {
    const at = curvePoint(path.start, path.end, path.control, lerp(from, to, i / STEPS));
    points.push(at.x, at.y);
  }
  return points;
}

const has = (frame: Frame, id: string, effect: "trail" | "arrow" | "ring" | "zoom") => {
  const item = frame.objects.find(other => other.id === id);
  return !!item && effectsOf(item).includes(effect);
};

/** The trail left on the move into `to`, up to progress `upTo` (eased); null without the effect or a move. */
export function trailOf(from: Frame, to: Frame, id: string, upTo: number): number[] | null {
  if (!has(to, id, "trail") || upTo <= 0) return null;
  const path = pathOf(from, to, id);
  return path && sample(path, 0, upTo);
}

/**
 * The arrow ahead on the move into `to` at progress t: drawn out quickly
 * along the whole way, then taken away behind the object as it goes; null
 * without the effect, a move, or once the object is there.
 */
export function arrowOf(from: Frame, to: Frame, id: string, t: number): number[] | null {
  if (!has(to, id, "arrow")) return null;
  const path = pathOf(from, to, id);
  if (!path) return null;
  const at = ease(to.easing, t);
  const reach = quick(t, 0.25);
  return reach - at < 0.02 ? null : sample(path, at, reach);
}

/** The ring coming on over the move into `to`; null without the effect. */
function ringOf(to: Frame, id: string, t: number): Ring | null {
  if (!has(to, id, "ring")) return null;
  const shown = quick(t);
  return { opacity: shown, grow: lerp(1.5, 1, shown) };
}

/**
 * The marks at a playhead added to the objects shown there: those of the
 * move under way, and those left on reaching the frame it starts from,
 * fading over it (fully there when standing on a frame).
 */
export function withMarks<T extends TacticsObject>(frames: Frame[], playhead: number, objects: T[]): (T & Marks)[] {
  if (frames.length === 0) return objects;
  const index = Math.min(frames.length - 1, Math.max(0, Math.floor(playhead)));
  const moving = index < frames.length - 1 && playhead - index > 0;
  const t = moving ? playhead - index : 0;
  return objects.map(item => {
    const trails: Trail[] = [];
    let ring: Ring | null = null;
    // Left on reaching this frame: fading as the next move goes.
    if (index > 0) {
      const left = trailOf(frames[index - 1], frames[index], item.id, 1);
      if (left) trails.push({ points: left, opacity: 1 - t });
      if (has(frames[index], item.id, "ring")) ring = { opacity: 1 - t, grow: 1 };
    }
    if (moving) {
      const [from, to] = [frames[index], frames[index + 1]];
      const trail = trailOf(from, to, item.id, ease(to.easing, t));
      if (trail) trails.push({ points: trail, opacity: 1 });
      const arrow = arrowOf(from, to, item.id, t);
      if (arrow) trails.push({ points: arrow, opacity: 1, arrow: true });
      const coming = ringOf(to, item.id, t);
      if (coming && (!ring || coming.opacity > ring.opacity)) ring = coming;
    }
    const marks: Marks = {};
    if (trails.length > 0) marks.trails = trails;
    if (ring && ring.opacity > 0) marks.ring = ring;
    return Object.keys(marks).length > 0 ? { ...item, ...marks } : item;
  });
}

/** Where the view looks while playing: a pitch point, and how far in (0 the whole view, 1 zoomed in). */
export type Camera = { at: Point; amount: number };

/** The object a frame zooms in on: the first with the zoom effect. */
const zoomedOn = (frame: Frame | undefined) => frame?.objects.find(item => effectsOf(item).includes("zoom"))?.id ?? null;

/**
 * The view at a playhead, following the zoomed object where it is shown
 * (`shown`, the objects at the playhead). Moving into a frame that zooms,
 * the view zooms in quickly and stays; a next frame that zooms too keeps
 * it in (gliding over to its object), one that does not zooms out again.
 * Null for the whole view.
 */
export function cameraAt(frames: Frame[], playhead: number, shown: TacticsObject[]): Camera | null {
  if (frames.length === 0) return null;
  const index = Math.min(frames.length - 1, Math.max(0, Math.floor(playhead)));
  const t = playhead - index;
  const where = (id: string, frame: Frame): Point | null =>
    shown.find(item => item.id === id) ?? frame.objects.find(item => item.id === id) ?? null;
  const here = zoomedOn(index > 0 ? frames[index] : undefined);
  if (index >= frames.length - 1 || t <= 0) {
    const at = here && where(here, frames[index]);
    return at ? { at: { x: at.x, y: at.y }, amount: 1 } : null;
  }
  const next = zoomedOn(frames[index + 1]);
  const step = quick(t);
  const nextAt = next && where(next, frames[index + 1]);
  const hereAt = here && where(here, frames[index]);
  if (nextAt) {
    if (hereAt) return { at: lerpPoint(hereAt, nextAt, step), amount: 1 };
    return { at: { x: nextAt.x, y: nextAt.y }, amount: step };
  }
  if (hereAt) return { at: { x: hereAt.x, y: hereAt.y }, amount: 1 - step };
  return null;
}
