// Drawing in a live lesson: a stroke is a line of pitch points in metres,
// thinned as it is drawn so it stays small to send, in the drawer's own
// colour. Pure, so it can be tested.
export type DrawMode = "off" | "own" | "shared";

export type Stroke = { id: string; board_id: string; profile_id: string; name: string; color: string; points: number[]; created_at: string };

export const drawModeLabels: Record<DrawMode, string> = { off: "Av", own: "Egna anteckningar", shared: "Gemensamt för alla" };

const COLORS = ["#ef4444", "#f59e0b", "#22c55e", "#06b6d4", "#3b82f6", "#a855f7", "#ec4899", "#f97316"];

/** A participant's colour, the same on every screen. */
export function colorFor(id: string): string {
  let hash = 0;
  for (const char of id) hash = (hash * 31 + char.charCodeAt(0)) | 0;
  return COLORS[Math.abs(hash) % COLORS.length];
}

const MAX_POINTS = 300;

/** The points kept of a drawn line: each at least `step` metres from the last, at most 300, the last always. */
export function thinStroke(points: number[], step = 0.3): number[] {
  if (points.length < 4) return points;
  const kept = [points[0], points[1]];
  for (let i = 2; i < points.length; i += 2) {
    const [x, y] = [points[i], points[i + 1]];
    if (Math.hypot(x - kept[kept.length - 2], y - kept[kept.length - 1]) >= step) kept.push(x, y);
  }
  const lastX = points[points.length - 2], lastY = points[points.length - 1];
  if (kept[kept.length - 2] !== lastX || kept[kept.length - 1] !== lastY) kept.push(lastX, lastY);
  if (kept.length / 2 <= MAX_POINTS) return kept.length >= 4 ? kept : [...kept, ...kept];
  // Too many still: every n-th point, the ends kept.
  const every = Math.ceil(kept.length / 2 / MAX_POINTS);
  const sampled: number[] = [];
  for (let i = 0; i < kept.length; i += 2 * every) sampled.push(kept[i], kept[i + 1]);
  sampled.push(lastX, lastY);
  return sampled.slice(0, MAX_POINTS * 2 - 2).concat([lastX, lastY]);
}

/** Strokes added once each, in the order drawn. */
export function mergeStrokes(list: Stroke[], incoming: Stroke[]): Stroke[] {
  const byId = new Map(list.map(stroke => [stroke.id, stroke]));
  for (const stroke of incoming) byId.set(stroke.id, stroke);
  return [...byId.values()].sort((a, b) => a.created_at.localeCompare(b.created_at));
}

export function drawError(message: string): string {
  if (message.includes("drawing_off")) return "Läraren har stängt av ritandet.";
  if (message.includes("too_fast")) return "Vänta en stund innan du ritar mer.";
  return "Det du ritade kunde inte skickas.";
}
