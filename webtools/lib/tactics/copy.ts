// Copying selected objects to another frame of the board, or to the first
// frame of another board. In the same board a copy keeps its id, so the
// object moves between the frames when played; one already in the frame is
// set as in the copy, keeping that frame's own effects and bend. Into
// another board copies get new ids, a ball staying with its player when
// both go. Effects and bends belong to a frame and do not go along.
import { settleBalls } from "./ball.ts";
import { newId, updateBoard } from "./document.ts";
import type { ProjectDocument, TacticsObject } from "./model.ts";

export type FramePlace = { boardId: string; frameIndex: number };

/** The document with the objects copied, the ids they have there, and how many replaced one already there. */
export function copyObjects(document: ProjectDocument, from: FramePlace, ids: string[], to: FramePlace):
  { document: ProjectDocument; ids: string[]; replaced: number } {
  const source = document.boards.find(board => board.id === from.boardId)?.frames[from.frameIndex];
  const target = document.boards.find(board => board.id === to.boardId)?.frames[to.frameIndex];
  const same = from.boardId === to.boardId && from.frameIndex === to.frameIndex;
  if (!source || !target || same) return { document, ids: [], replaced: 0 };
  const picked = source.objects.filter(item => ids.includes(item.id));
  const sameBoard = from.boardId === to.boardId;
  const renamed = new Map(picked.map(item => [item.id, sameBoard ? item.id : newId()]));

  const copies = picked.map(item => {
    const copy = { ...item, id: renamed.get(item.id)!, effects: [], effect: null, pathControl: null } as TacticsObject;
    if (copy.type === "ball" && copy.attachedTo) return { ...copy, attachedTo: renamed.get(copy.attachedTo) ?? copy.attachedTo };
    return copy;
  });
  const byId = new Map(copies.map(copy => [copy.id, copy]));
  let replaced = 0;
  const kept = target.objects.map(item => {
    const copy = byId.get(item.id);
    if (!copy) return item;
    replaced++;
    byId.delete(item.id);
    return { ...copy, effects: item.effects, effect: item.effect ?? null, pathControl: item.pathControl ?? null } as TacticsObject;
  });
  const objects = settleBalls([...kept, ...byId.values()]);
  const changed = updateBoard(document, to.boardId, board => ({
    ...board,
    frames: board.frames.map((frame, index) => index === to.frameIndex ? { ...frame, objects } : frame),
  }));
  return { document: changed, ids: copies.map(copy => copy.id), replaced };
}
