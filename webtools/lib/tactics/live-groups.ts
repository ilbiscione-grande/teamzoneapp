// Group work in a live lesson: each group has its own copy of the board, a
// sandbox thrown away when the host takes the floor back. A group's copy is
// the board as it was when the work started, plus where each moved object
// stands now, per frame. Pure, so it can be tested.
import { newId, updateFrame } from "./document.ts";
import type { ChatMessage } from "./live-chat.ts";
import { applyGroupEdits, type GroupEdits } from "./live-group-edits.ts";
import type { Stroke } from "./live-draw.ts";
import type { Board, FreehandObject, Point, ProjectDocument } from "./model.ts";
import { copyBoard } from "./templates.ts";

/** Where moved objects stand: by frame index, then object id. */
export type GroupMoves = Record<string, Record<string, Point>>;

export type GroupMember = { profile_id: string; name: string };

/** A group as the host lists it. */
export type LiveGroupSummary = { id: string; number: number; board_id: string; frame_index: number; members: GroupMember[] };

/** A group with its board and the moves so far: a participant's own, the one shown to everyone, or one in the host's overview. */
export type LiveGroup = LiveGroupSummary & {
  board: Board; moves: GroupMoves;
  /** Objects placed, changed and removed on the copy (step 4). */
  edits: GroupEdits;
  /** What the group drew on its copy, and its own chat (step 3). */
  strokes: Stroke[]; messages: ChatMessage[];
  /** Seconds left of the group work's time when read, 0 once out, null when there is none. */
  ends_in: number | null;
};

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

/** The group's board as it stands: the starting board with the edits, then the moves in place, balls and lines settled. */
export function groupBoard(board: Board, moves: GroupMoves, edits: GroupEdits = {}): Board {
  // updateFrame works on a document; only the boards matter to it.
  let document = { boards: [applyGroupEdits(board, edits)] } as ProjectDocument;
  for (const [frame, objects] of Object.entries(moves)) {
    const index = Number(frame);
    if (!Number.isInteger(index) || !board.frames[index] || Object.keys(objects).length === 0) continue;
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
  const board = groupBoard(group.board, group.moves, group.edits);
  return { view: board.view, teams: board.teams, objects: board.frames[group.frame_index]?.objects ?? [] };
}

/** A group's strokes as freehand lines on a board: placed at their first point, as the editor draws them. */
export function strokesAsFreehand(strokes: Stroke[]): FreehandObject[] {
  return strokes.filter(stroke => stroke.points.length >= 4).map(stroke => {
    const [x, y] = stroke.points;
    return {
      id: newId(), type: "freehand", x, y, rotation: 0, locked: false, hidden: false,
      points: stroke.points.map((value, index) => value - (index % 2 === 0 ? x : y)),
      arrow: "none", dashed: false, color: stroke.color, width: 0.3,
    };
  });
}

/** A group's solution as a board of its own for the project: the copy as it stands, the group's drawing on the group's frame, new ids. */
export function groupSolution(group: LiveGroup, name: string): Board {
  const board = copyBoard(groupBoard(group.board, group.moves, group.edits));
  const drawn = strokesAsFreehand(group.strokes);
  return {
    ...board, name: name.slice(0, 60),
    frames: board.frames.map((frame, index) => index === group.frame_index ? { ...frame, objects: [...frame.objects, ...drawn] } : frame),
  };
}

/** When the time runs out, in this browser's clock, from the seconds left when it was read. */
export const deadlineFrom = (seconds: number | null | undefined, now = Date.now()) => seconds === null || seconds === undefined ? null : now + seconds * 1000;

/** Time left as minutes and seconds, "0:00" once out. */
export function timeLeft(deadline: number, now = Date.now()): string {
  const seconds = Math.max(0, Math.ceil((deadline - now) / 1000));
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}

export function groupError(message: string): string {
  if (message.includes("invalid_group_count")) return "Välj mellan 2 och 6 grupper.";
  if (message.includes("invalid_board")) return "Tavlan kunde inte skickas till grupperna.";
  if (message.includes("invalid_group") || message.includes("invalid_participant")) return "Gruppen eller deltagaren finns inte längre.";
  if (message.includes("invalid_edit") || message.includes("too_large")) return "Ändringen kunde inte sparas i gruppens kopia.";
  if (message.includes("too_fast")) return "Vänta en stund innan du skickar mer.";
  if (message.includes("muted")) return "Läraren har stängt av chatten för dig.";
  if (message.includes("invalid_stroke")) return "Det du ritade kunde inte skickas.";
  if (message.includes("no_group")) return "Du är inte med i någon grupp längre.";
  return "Grupparbetet kunde inte ändras.";
}
