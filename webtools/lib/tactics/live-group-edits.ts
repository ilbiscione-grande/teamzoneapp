// Full editing on a group's copy in a live lesson (group work step 4): a
// change is sent per object, whole as it now stands or as removed, per
// frame. A group keeps them after its starting board. Here: applying edits
// to a board, finding what changed between two boards (what to send), and
// merging edits as the database does. Pure, so it can be tested.
import { updateFrame } from "./document.ts";
import type { Board, ProjectDocument, TacticsObject } from "./model.ts";

/** By frame index, then object id: the object as it now stands, or null when removed. */
export type GroupEdits = Record<string, Record<string, TacticsObject | null>>;

/** One frame's changes, as sent and as they come back on the channels. */
export type FrameEdit = { frameIndex: number; objects: Record<string, TacticsObject>; removed: string[] };

/** At most this many objects in one call; more are sent in several. */
export const EDITS_PER_CALL = 60;

/** One frame's objects with the changes in: changed ones in place, new ones last, removed ones gone. */
function editObjects(objects: TacticsObject[], changes: Record<string, TacticsObject | null>): TacticsObject[] {
  const known = new Set(objects.map(item => item.id));
  const kept = objects.filter(item => changes[item.id] !== null).map(item => changes[item.id] ?? item);
  const added = Object.values(changes).filter((item): item is TacticsObject => item !== null && !known.has(item.id));
  return [...kept, ...added];
}

/** The board with the edits in, frame by frame. */
export function applyGroupEdits(board: Board, edits: GroupEdits): Board {
  let document = { boards: [board] } as ProjectDocument;
  for (const [frame, changes] of Object.entries(edits)) {
    const index = Number(frame);
    if (!Number.isInteger(index) || !board.frames[index]) continue;
    document = updateFrame(document, board.id, index, objects => editObjects(objects, changes));
  }
  return document.boards[0];
}

/** One frame's changes applied to a whole document (the participant's editor). */
export function applyFrameEdit(document: ProjectDocument, boardId: string, edit: FrameEdit): ProjectDocument {
  const changes: Record<string, TacticsObject | null> = { ...edit.objects };
  for (const id of edit.removed) changes[id] = null;
  return updateFrame(document, boardId, edit.frameIndex, objects => editObjects(objects, changes));
}

/** What changed from one board to the next, per frame: objects not the same as before, and objects gone. */
export function boardEdits(before: Board, after: Board): FrameEdit[] {
  const edits: FrameEdit[] = [];
  after.frames.forEach((frame, frameIndex) => {
    const earlier = before.frames[frameIndex]?.objects ?? [];
    if (earlier === frame.objects) return;
    const was = new Map(earlier.map(item => [item.id, item]));
    const objects: Record<string, TacticsObject> = {};
    for (const item of frame.objects) if (was.get(item.id) !== item) objects[item.id] = item;
    const now = new Set(frame.objects.map(item => item.id));
    const removed = earlier.filter(item => !now.has(item.id)).map(item => item.id);
    if (Object.keys(objects).length || removed.length) edits.push({ frameIndex, objects, removed });
  });
  return edits;
}

/** A frame's changes split so no call carries more than EDITS_PER_CALL objects. */
export function splitEdit(edit: FrameEdit): FrameEdit[] {
  const entries = [...Object.entries(edit.objects).map(([id, item]) => ({ id, item })), ...edit.removed.map(id => ({ id, item: null }))];
  const parts: FrameEdit[] = [];
  for (let start = 0; start < entries.length; start += EDITS_PER_CALL) {
    const slice = entries.slice(start, start + EDITS_PER_CALL);
    parts.push({
      frameIndex: edit.frameIndex,
      objects: Object.fromEntries(slice.filter(entry => entry.item).map(entry => [entry.id, entry.item as TacticsObject])),
      removed: slice.filter(entry => !entry.item).map(entry => entry.id),
    });
  }
  return parts;
}

/** Edits added to those kept, as the database merges them. */
export function mergeGroupEdits(edits: GroupEdits, edit: FrameEdit): GroupEdits {
  const key = String(edit.frameIndex);
  const removed = Object.fromEntries(edit.removed.map(id => [id, null]));
  return { ...edits, [key]: { ...edits[key], ...edit.objects, ...removed } };
}
