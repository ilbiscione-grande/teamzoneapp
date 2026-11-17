// Group work in a live lesson: each group has its own copy of the board, a
// sandbox thrown away when the host takes the floor back. A group's copy is
// the board as it was when the work started, plus where each moved object
// stands now, per frame. Pure, so it can be tested.
import { updateFrame } from "./document.ts";
import type { Board, Point, ProjectDocument } from "./model.ts";

/** Where moved objects stand: by frame index, then object id. */
export type GroupMoves = Record<string, Record<string, Point>>;

export type GroupMember = { profile_id: string; name: string };

/** A group as the host lists it. */
export type LiveGroupSummary = { id: string; number: number; board_id: string; frame_index: number; members: GroupMember[] };

/** A participant's own group, with its board and the moves so far. */
export type LiveGroup = LiveGroupSummary & { board: Board; moves: GroupMoves };

export const groupTopic = (groupId: string) => `tactics-live-group:${groupId}`;

export const MIN_GROUPS = 2;
export const MAX_GROUPS = 6;

/** The group counts the host can choose with this many participants: 2 up to one per participant, at most 6. */
export function groupCounts(participants: number): number[] {
  const most = Math.min(MAX_GROUPS, Math.max(MIN_GROUPS, participants));
  return Array.from({ length: most - MIN_GROUPS + 1 }, (_, index) => MIN_GROUPS + index);
}

/** The group's board as it stands: the starting board with the moves in place, balls and lines settled. */
export function groupBoard(board: Board, moves: GroupMoves): Board {
  // updateFrame works on a document; only the boards matter to it.
  let document = { boards: [board] } as ProjectDocument;
  for (const [frame, objects] of Object.entries(moves)) {
    const index = Number(frame);
    if (!Number.isInteger(index) || !board.frames[index]) continue;
    document = updateFrame(document, board.id, index, items => items.map(item => objects[item.id] ? { ...item, ...objects[item.id] } : item));
  }
  return document.boards[0];
}

/** Moves added to those kept, as the database merges them. */
export function mergeGroupMoves(moves: GroupMoves, frameIndex: number, incoming: Record<string, Point>): GroupMoves {
  const key = String(frameIndex);
  return { ...moves, [key]: { ...moves[key], ...incoming } };
}

export function groupError(message: string): string {
  if (message.includes("invalid_group_count")) return "Välj mellan 2 och 6 grupper.";
  if (message.includes("invalid_board")) return "Tavlan kunde inte skickas till grupperna.";
  if (message.includes("no_group")) return "Du är inte med i någon grupp längre.";
  return "Grupparbetet kunde inte ändras.";
}
