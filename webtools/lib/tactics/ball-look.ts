// What the ball looks like: a football's panels as seen from above, a black
// pentagon in the middle with five more at the edge, cut off by the ball's
// rim, and the seams between them. In the ball's own units around its
// centre, for the board (Konva) and the small pictures (SVG) alike.

export type BallPattern = { middle: number[]; edge: number[][]; seams: number[][] };

const pentagon = (cx: number, cy: number, radius: number, turn: number): number[] =>
  Array.from({ length: 5 }, (_, index) => {
    const angle = turn + (index * 2 * Math.PI) / 5;
    return [cx + radius * Math.cos(angle), cy + radius * Math.sin(angle)];
  }).flat();

/** The panels of a ball of the given radius, as flat [x, y, x, y, …] lists. */
export function ballPattern(radius: number): BallPattern {
  const up = -Math.PI / 2;
  const inner = radius * 0.4, outer = radius * 0.36, reach = radius * 1.04;
  const middle = pentagon(0, 0, inner, up);
  const edge: number[][] = [], seams: number[][] = [];
  for (let index = 0; index < 5; index++) {
    const angle = up + (index * 2 * Math.PI) / 5;
    const cx = reach * Math.cos(angle), cy = reach * Math.sin(angle);
    // Pointing at the middle, as on a ball.
    edge.push(pentagon(cx, cy, outer, angle + Math.PI));
    seams.push([inner * Math.cos(angle), inner * Math.sin(angle), (reach - outer) * Math.cos(angle), (reach - outer) * Math.sin(angle)]);
  }
  // The white panels' outer sides: from each edge panel's corner nearest the next to that one's nearest corner.
  const corners = (panel: number[]) => [0, 1, 2, 3, 4].map(index => [panel[index * 2], panel[index * 2 + 1]]);
  for (let index = 0; index < 5; index++) {
    const here = corners(edge[index]), next = corners(edge[(index + 1) % 5]);
    let best: number[] = [], gap = Infinity;
    for (const a of here) for (const b of next) {
      const length = Math.hypot(a[0] - b[0], a[1] - b[1]);
      if (length < gap) { gap = length; best = [...a, ...b]; }
    }
    seams.push(best);
  }
  return { middle, edge, seams };
}

/** Points as an SVG polygon's "points". */
export const svgPoints = (points: number[]) => points.map(value => value.toFixed(3)).join(" ");
