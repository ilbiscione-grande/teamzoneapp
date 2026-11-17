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

/** A group with its board and the moves so far: a participant's own, the one shown to everyone, or one in the host's overview. */
export type LiveGroup = LiveGroupSummary & { board: Board; moves: GroupMoves };

/** A group in the host's overview: whether it is shown to everyone. */
export type HostGroup = LiveGroup & { shown: boolean };

/** A move in a group, on the group's channel, and on the lesson's while the group is shown. */
export type GroupMove = { groupId: string; boardId: string; frameIndex: number; moves: Record<string, Point>; dropped: boolean; by: string };

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

/** What a small picture of the group's copy needs: the view, the teams and the objects on the group's frame as they stand. */
export function groupPreview(group: LiveGroup): { view: Board["view"]; teams: Board["teams"]; objects: Board["frames"][number]["objects"] } {
  const board = groupBoard(group.board, group.moves);
  return { view: board.view, teams: board.teams, objects: board.frames[group.frame_index]?.objects ?? [] };
}

export function groupError(message: string): string {
  if (message.includes("invalid_group_count")) return "Välj mellan 2 och 6 grupper.";
  if (message.includes("invalid_board")) return "Tavlan kunde inte skickas till grupperna.";
  if (message.includes("invalid_group") || message.includes("invalid_participant")) return "Gruppen eller deltagaren finns inte längre.";
  if (message.includes("no_group")) return "Du är inte med i någon grupp längre.";
  return "Grupparbetet kunde inte ändras.";
}
