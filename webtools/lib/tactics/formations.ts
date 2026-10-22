// Formations as lines from the back: "4-3-3" is four, three and three in
// front of the goalkeeper. A side's players are placed on its own half, the
// home team attacking to the right.
import { PITCH_LENGTH, PITCH_WIDTH, type Point, type Side } from "./model.ts";

export const formations: Record<string, number[]> = {
  "4-3-3": [4, 3, 3],
  "4-4-2": [4, 4, 2],
  "4-2-3-1": [4, 2, 3, 1],
  "4-1-4-1": [4, 1, 4, 1],
  "4-3-1-2": [4, 3, 1, 2],
  "4-5-1": [4, 5, 1],
  "3-5-2": [3, 5, 2],
  "3-4-3": [3, 4, 3],
  "5-3-2": [5, 3, 2],
  "5-4-1": [5, 4, 1],
  // Small-sided football.
  "3-2-1 (7 mot 7)": [3, 2, 1],
  "2-3-1 (7 mot 7)": [2, 3, 1],
  "3-3-2 (9 mot 9)": [3, 3, 2],
  "3-4-1 (9 mot 9)": [3, 4, 1],
  "2-1-1 (5 mot 5)": [2, 1, 1],
};

/** The goalkeeper first, then each line from the back, top to bottom. */
export function formationPositions(lines: number[], side: Side): Point[] {
  const depth = PITCH_LENGTH / 2;
  const goalkeeper = 4;
  // Lines spread between the own penalty area and just short of halfway.
  const first = 16;
  const last = depth - 4;
  const step = lines.length > 1 ? (last - first) / (lines.length - 1) : 0;
  const positions: Point[] = [{ x: goalkeeper, y: PITCH_WIDTH / 2 }];
  lines.forEach((count, index) => {
    const x = first + step * index;
    for (let slot = 0; slot < count; slot++) {
      const y = (PITCH_WIDTH * (slot + 1)) / (count + 1);
      positions.push({ x, y });
    }
  });
  // The away team mirrors to the other half.
  return side === "home" ? positions : positions.map(point => ({ x: PITCH_LENGTH - point.x, y: PITCH_WIDTH - point.y }));
}

/** "4-3-3" → [4, 3, 3]; null for anything that is not a formation. */
export function parseFormation(text: string): number[] | null {
  const parts = text.trim().split(/\s*-\s*/).map(Number);
  if (parts.length < 2 || parts.some(n => !Number.isInteger(n) || n < 1 || n > 6)) return null;
  const outfield = parts.reduce((sum, n) => sum + n, 0);
  return outfield >= 3 && outfield <= 10 ? parts : null;
}
