// Groups and copies: objects of one group are chosen, moved and copied as
// one (a set-up of cones with its players). A group is the same id on each
// object, on every frame of the board, so it holds through the animation.
import { newId } from "./document.ts";
import type { Board, TacticsObject } from "./model.ts";

/** The ids with the rest of each one's group. */
export function withGroups(objects: TacticsObject[], ids: string[]): string[] {
  const groups = new Set(objects.filter(item => item.group && ids.includes(item.id)).map(item => item.group));
  if (groups.size === 0) return ids;
  return [...new Set([...ids, ...objects.filter(item => item.group && groups.has(item.group)).map(item => item.id)])];
}

/** Whether the objects are all of one group. */
export function oneGroup(objects: TacticsObject[], ids: string[]): boolean {
  const chosen = objects.filter(item => ids.includes(item.id));
  return chosen.length > 1 && !!chosen[0].group && chosen.every(item => item.group === chosen[0].group);
}

/** The board with the objects put in a new group (or out of theirs: null) in every frame. */
export function setGroup(board: Board, ids: string[], group: string | null): Board {
  const chosen = new Set(ids);
  return {
    ...board,
    frames: board.frames.map(frame => ({
      ...frame,
      objects: frame.objects.map(item => (chosen.has(item.id) ? { ...item, group: group ?? undefined } : item)),
    })),
  };
}

/** Copies of the objects a little aside, unlocked; copies of one group make a new group of their own. */
export function copiesOf(objects: TacticsObject[], ids: string[]): TacticsObject[] {
  const groups = new Map<string, string>();
  return objects.filter(item => ids.includes(item.id)).map(item => {
    const group = item.group ? (groups.get(item.group) ?? groups.set(item.group, newId()).get(item.group)) : undefined;
    return { ...item, id: newId(), x: item.x + 3, y: item.y + 3, locked: false, group } as TacticsObject;
  });
}
