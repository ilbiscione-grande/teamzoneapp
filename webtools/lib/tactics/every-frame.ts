// What is chosen for an object in every frame it is in, rather than in the
// frame in hand: a colour or an effect. A locked copy is left as it is. An
// effect chosen so is also remembered on the object (lastingEffects), so a
// frame added later has it too, unless that is turned off for the object.
import { toggleEffect } from "./document.ts";
import type { Board, Effect, TacticsObject } from "./model.ts";
import { effectsOf } from "./motion.ts";

function eachCopy(board: Board, change: (item: TacticsObject) => TacticsObject | null): Board {
  return {
    ...board,
    frames: board.frames.map(frame => ({ ...frame, objects: frame.objects.map(item => (item.locked ? null : change(item)) ?? item) })),
  };
}

/** Patches by object id, in every frame the object is in. */
export function patchEveryFrame(board: Board, patches: Record<string, Partial<TacticsObject>>): Board {
  return eachCopy(board, item => (patches[item.id] ? ({ ...item, ...patches[item.id] } as TacticsObject) : null));
}

/** One effect on or off for these objects in every frame they are in, and in frames added later. */
export function setEffectEveryFrame(board: Board, ids: string[], kind: Effect, on: boolean): Board {
  const chosen = new Set(ids);
  return eachCopy(board, item => {
    if (!chosen.has(item.id)) return null;
    const lasting = (item.lastingEffects ?? []).filter(other => other !== kind);
    return { ...item, ...toggleEffect(item, kind, on), lastingEffects: on ? [...lasting, kind] : lasting } as TacticsObject;
  });
}

/** Which effects frames added later give the object, whatever it has now: all of `effects`, or none. */
export function setLastingEffects(board: Board, id: string, effects: Effect[]): Board {
  return eachCopy(board, item => (item.id === id ? { ...item, lastingEffects: effects } : null));
}

/** Whether a frame added after this copy gets all its effects. */
export function effectsLast(item: TacticsObject): boolean {
  const effects = effectsOf(item);
  return effects.length > 0 && effects.every(kind => item.lastingEffects?.includes(kind));
}

/** Whether every copy of the object that can be changed has the effect. */
export function hasEffectEveryFrame(board: Board, id: string, kind: Effect): boolean {
  const copies = board.frames.flatMap(frame => frame.objects.filter(item => item.id === id && !item.locked));
  return copies.length > 0 && copies.every(item => effectsOf(item).includes(kind));
}
