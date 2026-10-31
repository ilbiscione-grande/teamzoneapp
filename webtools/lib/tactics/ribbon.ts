// The broadcast look of drawn marks, as outlines to fill: a pass as a flat
// band that widens from its start into a broad arrowhead, an arrowhead on its
// own (for runs and dribbles, whose line stays a stroke), and the stripes that
// hatch an area. Points are flat lists x, y, … in metres.

/** How wide a band is for a line of this width, and how large its head. */
export function bandSizes(width: number) {
  const body = Math.max(0.7, width * 2.6);
  return { body, headLength: Math.max(2, body * 2.8), headWidth: body * 2.6 };
}

type P = { x: number; y: number };

const toPoints = (flat: number[]): P[] => {
  const points: P[] = [];
  for (let index = 0; index + 1 < flat.length; index += 2) {
    const point = { x: flat[index], y: flat[index + 1] };
    const last = points[points.length - 1];
    if (!last || Math.hypot(point.x - last.x, point.y - last.y) > 1e-4) points.push(point);
  }
  return points;
};

const lengthOf = (points: P[]) => points.slice(1).reduce((sum, point, index) => sum + Math.hypot(point.x - points[index].x, point.y - points[index].y), 0);

/** The path cut short by `cut` metres at its end (and at its start too when `both`). */
function trimmed(points: P[], start: number, end: number): P[] {
  const total = lengthOf(points);
  const from = Math.min(start, total), to = Math.max(from, total - end);
  const result: P[] = [];
  let walked = 0;
  for (let index = 1; index < points.length; index++) {
    const a = points[index - 1], b = points[index];
    const step = Math.hypot(b.x - a.x, b.y - a.y);
    const at = (along: number) => ({ x: a.x + ((b.x - a.x) * (along - walked)) / step, y: a.y + ((b.y - a.y) * (along - walked)) / step });
    if (walked + step >= from && result.length === 0) result.push(at(from));
    if (walked + step >= to) { result.push(at(to)); break; }
    if (walked + step > from) result.push(b);
    walked += step;
  }
  return result;
}

/** The way a path heads at its end (or at its start, backwards), as a unit vector. */
function heading(points: P[], atEnd: boolean): P {
  const [a, b] = atEnd ? [points[points.length - 2], points[points.length - 1]] : [points[1], points[0]];
  const length = Math.hypot(b.x - a.x, b.y - a.y) || 1;
  return { x: (b.x - a.x) / length, y: (b.y - a.y) / length };
}

/** A triangle arrowhead with its tip at `tip`, pointing along `way`. */
function head(tip: P, way: P, length: number, width: number): number[] {
  const base = { x: tip.x - way.x * length, y: tip.y - way.y * length };
  const side = { x: -way.y * (width / 2), y: way.x * (width / 2) };
  return [base.x + side.x, base.y + side.y, tip.x, tip.y, base.x - side.x, base.y - side.y];
}

/** Arrowheads alone, for a line drawn as a stroke: at the end, or at both ends. */
export function arrowHeads(flat: number[], width: number, both: boolean): number[][] {
  const points = toPoints(flat);
  if (points.length < 2) return [];
  const { headLength, headWidth } = bandSizes(width);
  const length = Math.min(headLength, lengthOf(points) * 0.45);
  const heads = [head(points[points.length - 1], heading(points, true), length, headWidth * (length / headLength))];
  if (both) heads.push(head(points[0], heading(points, false), length, headWidth * (length / headLength)));
  return heads;
}

/** How far back a stroke stops so its arrowhead's tip is the line's end. */
export function headRoom(flat: number[], width: number): number {
  const points = toPoints(flat);
  return Math.min(bandSizes(width).headLength, lengthOf(points) * 0.45) * 0.6;
}

/** The path stopped short at its arrowheads, so a wide stroke does not poke out past their tips. */
export function shortened(flat: number[], width: number, arrow: "none" | "end" | "both"): number[] {
  if (arrow === "none") return flat;
  const points = toPoints(flat);
  if (points.length < 2) return flat;
  const room = headRoom(flat, width);
  return trimmed(points, arrow === "both" ? room : 0, room).flatMap(point => [point.x, point.y]);
}

/**
 * A pass as one outline: a band that starts narrow and widens to its full
 * width over the first third, then a broad arrowhead (at both ends when
 * asked; then the band keeps its width). Without a head it ends square.
 */
export function band(flat: number[], width: number, arrow: "none" | "end" | "both"): number[] {
  const points = toPoints(flat);
  if (points.length < 2) return [];
  const { body, headLength, headWidth } = bandSizes(width);
  const total = lengthOf(points);
  const tipLength = arrow === "none" ? 0 : Math.min(headLength, total * 0.45);
  const scale = headLength > 0 ? tipLength / headLength : 0;
  const path = trimmed(points, arrow === "both" ? tipLength : 0, tipLength);
  if (path.length < 2) return [];
  const along = lengthOf(path);
  const left: P[] = [], right: P[] = [];
  let walked = 0;
  path.forEach((point, index) => {
    if (index > 0) walked += Math.hypot(point.x - path[index - 1].x, point.y - path[index - 1].y);
    const a = path[Math.max(0, index - 1)], b = path[Math.min(path.length - 1, index + 1)];
    const length = Math.hypot(b.x - a.x, b.y - a.y) || 1;
    const normal = { x: -(b.y - a.y) / length, y: (b.x - a.x) / length };
    // Narrow at the start of a one-way pass, full from a third along.
    const share = arrow === "both" ? 1 : Math.min(1, 0.3 + (0.7 * walked) / Math.max(along / 3, 1e-6));
    const half = (body * share) / 2;
    left.push({ x: point.x + normal.x * half, y: point.y + normal.y * half });
    right.push({ x: point.x - normal.x * half, y: point.y - normal.y * half });
  });
  const outline: number[] = [];
  const tipAt = (atEnd: boolean) => {
    const way = heading(points, atEnd);
    const tip = atEnd ? points[points.length - 1] : points[0];
    const base = { x: tip.x - way.x * tipLength, y: tip.y - way.y * tipLength };
    const side = { x: -way.y * ((headWidth * scale) / 2), y: way.x * ((headWidth * scale) / 2) };
    return { tip, wing: { x: base.x + side.x, y: base.y + side.y }, other: { x: base.x - side.x, y: base.y - side.y } };
  };
  if (arrow === "both") {
    const start = tipAt(false);
    outline.push(start.other.x, start.other.y, start.tip.x, start.tip.y, start.wing.x, start.wing.y);
  }
  left.forEach(point => outline.push(point.x, point.y));
  if (arrow !== "none") {
    const end = tipAt(true);
    outline.push(end.wing.x, end.wing.y, end.tip.x, end.tip.y, end.other.x, end.other.y);
  }
  [...right].reverse().forEach(point => outline.push(point.x, point.y));
  return outline;
}

/**
 * Diagonal stripes over a box centred on 0, 0 (width × height), each as a
 * line x1, y1, x2, y2 reaching past the box: clipped to the area they hatch.
 */
export function stripes(width: number, height: number, gap: number): number[][] {
  const reach = (width + height) / 2 + 1, rise = height / 2 + 1;
  const lines: number[][] = [];
  for (let offset = -reach; offset <= reach; offset += gap) lines.push([offset - rise, rise, offset + rise, -rise]);
  return lines;
}

/** A colour's lightness (0 dark – 1 light), for an edge that shows against it. */
export function lightness(hex: string): number {
  const value = hex.replace("#", "");
  if (value.length < 6) return 1;
  const [r, g, b] = [0, 2, 4].map(index => parseInt(value.slice(index, index + 2), 16) / 255);
  return 0.299 * r + 0.587 * g + 0.114 * b;
}

/** The edge round a mark: dark round light colours, white round dark ones. */
export const edgeFor = (hex: string) => (lightness(hex) > 0.55 ? "rgba(11,17,28,0.55)" : "rgba(255,255,255,0.85)");
