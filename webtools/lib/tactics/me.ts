// "I am number 7": someone watching a shared link picks their own number
// and that player is marked on every board. The home team is taken as the
// one watching (the coach's own team); the choice stays in the browser,
// per link.
import type { Board, TacticsObject } from "./model.ts";

export type MyChoice = { number: number; name: string | null };

/** The home team's numbers on the boards, each once, with a name where one board has it. */
export function numbersOn(boards: Board[]): MyChoice[] {
  const found = new Map<number, string | null>();
  for (const board of boards) for (const frame of board.frames) for (const item of frame.objects) {
    if (item.type !== "player" || item.side !== "home" || item.number === null || item.hidden) continue;
    const name = item.name?.trim() || null;
    if (!found.has(item.number) || (!found.get(item.number) && name)) found.set(item.number, name);
  }
  return [...found].map(([number, name]) => ({ number, name })).sort((a, b) => a.number - b.number);
}

/** Whether this is the one watching. */
export const isMe = (item: TacticsObject, me: number | null) => me !== null && item.type === "player" && item.side === "home" && item.number === me;

/** Where the choice is kept: per link, so another team's link starts afresh. */
export const myNumberKey = (path: string) => `tz-tactics-me:${path}`;
