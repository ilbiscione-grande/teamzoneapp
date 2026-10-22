// Live lessons: what the host sends over the session's channel and how a
// participant applies it. The host sends where the board is (board, frame,
// playhead, playing), the board in hand when it changes, objects while they
// are dragged, and a pointer; participants only listen. Pure, so it can be
// tested and later replayed.
import { updateFrame } from "./document.ts";
import type { ChatMode } from "./live-chat.ts";
import type { DrawMode } from "./live-draw.ts";
import type { Board, Point, ProjectDocument, ProjectKind } from "./model.ts";

export type LiveSession = {
  id: string; code: string; project_id: string; allow_guests: boolean; live: boolean; chat_mode: ChatMode; hands: boolean;
  draw_mode: DrawMode; floor_holder: string | null; floor_name: string | null; created_at: string;
};

export type LiveJoined = LiveSession & {
  name: string; kind: ProjectKind; document: unknown; participant_name: string; host_name: string; muted: boolean;
};

/** Where the host's board is. A playing board is played on locally from the playhead. */
export type LiveView = { boardId: string; frameIndex: number; playhead: number; playing: boolean; speed: number; loop: boolean };

export type LiveEvent =
  | { event: "view"; payload: LiveView }
  | { event: "board"; payload: { board: Board } }
  | { event: "pointer"; payload: { point: Point | null } }
  | { event: "drag"; payload: LiveDrag }
  | { event: "guests-off"; payload: Record<string, never> }
  | { event: "ended"; payload: Record<string, never> };

/** Objects on their way while the host drags them: where each is now. */
export type LiveDrag = { boardId: string; frameIndex: number; moves: Record<string, Point> };

/** Who is on the channel: the host, or a participant with their name, hand (when raised) and whether their chat is off. */
export type LivePresence = { role: "host" | "participant"; name: string; guest: boolean; hand?: number | null; muted?: boolean };

export const liveTopic = (sessionId: string) => `tactics-live:${sessionId}`;

/** A code as typed: letters and digits, upper case; null when it cannot be one. */
export function normalizeCode(value: string): string | null {
  const code = value.toUpperCase().replace(/[^A-Z0-9]/g, "");
  return /^[A-HJ-NP-Z2-9]{6}$/.test(code) ? code : null;
}

export const liveLink = (origin: string, code: string) => `${origin}/live/${code}`;

/** The document with one board replaced (or added, when new to the participant). */
export function applyBoard(document: ProjectDocument, board: Board): ProjectDocument {
  const known = document.boards.some(item => item.id === board.id);
  return { ...document, boards: known ? document.boards.map(item => item.id === board.id ? board : item) : [...document.boards, board] };
}

/** The dragged objects moved in the participant's copy; balls held by a moved player go along. */
export function applyMoves(document: ProjectDocument, drag: LiveDrag): ProjectDocument {
  return updateFrame(document, drag.boardId, drag.frameIndex, objects =>
    objects.map(item => drag.moves[item.id] ? { ...item, ...drag.moves[item.id] } : item));
}

/** Whether two views differ enough to send: anything but the playhead while playing (played on locally). */
export function viewChanged(before: LiveView | null, after: LiveView): boolean {
  if (!before) return true;
  if (before.boardId !== after.boardId || before.playing !== after.playing || before.speed !== after.speed || before.loop !== after.loop) return true;
  if (after.playing) return false;
  return before.frameIndex !== after.frameIndex || Math.abs(before.playhead - after.playhead) > 1e-6;
}

/** Messages from the join call as the participant reads them. */
export function joinError(message: string): string {
  if (message.includes("login_required")) return "Läraren kräver inloggning för den här lektionen.";
  if (message.includes("invalid_name")) return "Skriv ditt namn, högst 40 tecken.";
  if (message.includes("not_found")) return "Det finns ingen pågående lektion med den koden.";
  return "Det gick inte att gå med. Försök igen.";
}

/** Calls fn at most every `ms`, with the last call made at the end. */
export function throttle<A extends unknown[]>(fn: (...args: A) => void, ms: number) {
  let last = 0;
  let pending: A | null = null;
  let timer: ReturnType<typeof setTimeout> | null = null;
  const run = () => {
    timer = null;
    if (!pending) return;
    const args = pending;
    pending = null;
    last = Date.now();
    fn(...args);
  };
  return {
    call: (...args: A) => {
      pending = args;
      const wait = ms - (Date.now() - last);
      if (wait <= 0) run();
      else if (!timer) timer = setTimeout(run, wait);
    },
    cancel: () => { if (timer) clearTimeout(timer); timer = null; pending = null; },
  };
}

/** A lesson with nothing happening ends after 30 minutes; the host is warned 5 minutes before. */
export const IDLE_LIMIT_MS = 30 * 60_000;
export const IDLE_WARNING_MS = 25 * 60_000;

export function idleState(lastActivity: number, now: number): "active" | "warning" | "expired" {
  const idle = now - lastActivity;
  return idle >= IDLE_LIMIT_MS ? "expired" : idle >= IDLE_WARNING_MS ? "warning" : "active";
}
