// Undo and redo as whole documents: small, and nothing to get wrong when a
// change touches several objects at once.
import type { ProjectDocument } from "./model.ts";

export const HISTORY_LIMIT = 60;

export type History = { past: ProjectDocument[]; future: ProjectDocument[] };

export const emptyHistory = (): History => ({ past: [], future: [] });

/** Remembers the document before a change; a new change ends redo. */
export function record(history: History, before: ProjectDocument): History {
  const past = [...history.past, before];
  return { past: past.length > HISTORY_LIMIT ? past.slice(past.length - HISTORY_LIMIT) : past, future: [] };
}

export function undo(history: History, current: ProjectDocument): { history: History; document: ProjectDocument } | null {
  const previous = history.past[history.past.length - 1];
  if (!previous) return null;
  return { document: previous, history: { past: history.past.slice(0, -1), future: [current, ...history.future] } };
}

export function redo(history: History, current: ProjectDocument): { history: History; document: ProjectDocument } | null {
  const next = history.future[0];
  if (!next) return null;
  return { document: next, history: { past: [...history.past, current], future: history.future.slice(1) } };
}
