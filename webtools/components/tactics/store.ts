"use client";

// The editor's state: the project being edited, the active board and frame,
// what is selected and which tool is in hand. Every change to the document
// goes through `change`, which remembers the step for undo and marks the
// project for saving.
import { create } from "zustand";
import { patchObjects, updateFrame } from "../../lib/tactics/document.ts";
import { emptyHistory, record, redo, undo, type History } from "../../lib/tactics/history.ts";
import type { Board, Project, ProjectDocument, ProjectKind, TacticsObject } from "../../lib/tactics/model.ts";

export type Tool =
  | "select"
  | "player-home" | "player-away" | "ball" | "cone" | "pole" | "mannequin" | "goal" | "text"
  | "arrow" | "run" | "line" | "freehand" | "rect" | "ellipse";

export type SaveState = "saved" | "dirty" | "saving" | "error" | "conflict";

export type ProjectMeta = { id: string; name: string; kind: ProjectKind; teamId: string | null; teamName: string | null; revision: number };

type EditorState = {
  meta: ProjectMeta | null;
  document: ProjectDocument | null;
  boardId: string | null;
  frameIndex: number;
  selection: string[];
  tool: Tool;
  /** Whether a dropped ball sticks to a nearby player. */
  attachBall: boolean;
  history: History;
  saveState: SaveState;
  /** Playing: where the playhead is (in frames), and how. */
  playing: boolean;
  playhead: number;
  loop: boolean;
  speed: number;
  /** Playing one move only (an effect's preview): the frame it stops on. */
  stopAt: number | null;
  /** Counted up to play on afresh from a new playhead while playing (a live lesson's host). */
  playSeq: number;
  setFrame: (index: number) => void;
  play: () => void;
  /** Plays the move into a frame and stops there, keeping the selection. */
  preview: (index: number) => void;
  /** The playhead moved by hand on the timeline: paused there, between frames too. */
  scrub: (playhead: number) => void;
  pause: () => void;
  setPlayhead: (playhead: number) => void;
  setLoop: (loop: boolean) => void;
  setSpeed: (speed: number) => void;
  load: (project: Project, document: ProjectDocument) => void;
  setTool: (tool: Tool) => void;
  setAttachBall: (value: boolean) => void;
  select: (ids: string[], additive?: boolean) => void;
  setBoard: (boardId: string) => void;
  /** A document change: remembered for undo, then saved. */
  change: (next: (document: ProjectDocument) => ProjectDocument) => void;
  /** A change to the active frame's objects. */
  changeObjects: (next: (objects: TacticsObject[]) => TacticsObject[]) => void;
  patch: (patches: Record<string, Partial<TacticsObject>>) => void;
  removeSelected: () => void;
  setMeta: (meta: Partial<Pick<ProjectMeta, "name" | "kind" | "teamId" | "teamName">>) => void;
  undo: () => void;
  redo: () => void;
  setSaveState: (state: SaveState) => void;
  saved: (revision: number, document: ProjectDocument) => void;
};

export const useEditor = create<EditorState>((set, get) => ({
  meta: null,
  document: null,
  boardId: null,
  frameIndex: 0,
  selection: [],
  tool: "select",
  attachBall: true,
  history: emptyHistory(),
  saveState: "saved",
  playing: false,
  playhead: 0,
  loop: false,
  speed: 1,
  stopAt: null,
  playSeq: 0,

  setFrame: index => {
    const board = activeBoard(get());
    if (!board) return;
    const frameIndex = Math.min(board.frames.length - 1, Math.max(0, index));
    set({ frameIndex, playhead: frameIndex, playing: false, selection: [] });
  },
  // From where it was stopped (between two frames too), or from the start when at the end.
  play: () => {
    const board = activeBoard(get());
    if (!board || board.frames.length < 2) return;
    const start = get().playhead >= board.frames.length - 1 ? 0 : get().playhead;
    set({ playing: true, playhead: start, stopAt: null, selection: [], tool: "select" });
  },
  preview: index => {
    const board = activeBoard(get());
    if (!board || index < 1 || index >= board.frames.length) return;
    set({ playing: true, playhead: index - 1, stopAt: index, tool: "select" });
  },
  // Paused between two frames, the board stays there; choosing a frame goes back to editing.
  pause: () => set(state => ({ playing: false, frameIndex: Math.round(state.playhead), stopAt: null })),
  scrub: playhead => {
    const board = activeBoard(get());
    if (!board) return;
    const clamped = Math.min(board.frames.length - 1, Math.max(0, playhead));
    set({ playing: false, stopAt: null, playhead: clamped, frameIndex: Math.round(clamped), selection: [] });
  },
  setPlayhead: playhead => set({ playhead }),
  setLoop: loop => set({ loop }),
  setSpeed: speed => set({ speed }),

  load: (project, document) => set({
    meta: { id: project.id, name: project.name, kind: project.kind, teamId: project.teamzone_team_id, teamName: project.team_name, revision: project.revision },
    document, boardId: document.boards[0]?.id ?? null, frameIndex: 0, selection: [], tool: "select", playing: false, playhead: 0,
    history: emptyHistory(), saveState: "saved",
  }),
  setTool: tool => set({ tool, selection: tool === "select" ? get().selection : [] }),
  setAttachBall: attachBall => set({ attachBall }),
  select: (ids, additive = false) => set(state => ({
    selection: additive ? [...new Set([...state.selection.filter(id => !ids.includes(id)), ...ids.filter(id => !state.selection.includes(id))])] : ids,
  })),
  setBoard: boardId => set({ boardId, frameIndex: 0, playhead: 0, playing: false, selection: [] }),

  change: next => {
    const { document, history } = get();
    if (!document) return;
    const changed = next(document);
    if (changed === document) return;
    set({ document: changed, history: record(history, document), saveState: "dirty" });
  },
  changeObjects: next => {
    const { boardId, frameIndex } = get();
    if (!boardId) return;
    get().change(document => updateFrame(document, boardId, frameIndex, next));
  },
  patch: patches => get().changeObjects(objects => patchObjects(objects, patches)),
  removeSelected: () => {
    const selected = new Set(get().selection);
    if (selected.size === 0) return;
    get().changeObjects(objects => objects.filter(item => !selected.has(item.id) || item.locked));
    set({ selection: [] });
  },
  setMeta: meta => set(state => state.meta ? { meta: { ...state.meta, ...meta }, saveState: "dirty" } : {}),

  undo: () => {
    const { document, history } = get();
    const step = document && undo(history, document);
    if (step) set(state => ({ document: step.document, history: step.history, saveState: "dirty", selection: [], ...frameWithin(step.document, state) }));
  },
  redo: () => {
    const { document, history } = get();
    const step = document && redo(history, document);
    if (step) set(state => ({ document: step.document, history: step.history, saveState: "dirty", selection: [], ...frameWithin(step.document, state) }));
  },
  setSaveState: saveState => set({ saveState }),
  // Saved as of this document; edits made meanwhile stay to be saved.
  saved: (revision, document) => set(state => ({
    meta: state.meta ? { ...state.meta, revision } : null,
    saveState: state.document === document ? "saved" : "dirty",
  })),
}));

/** One empty list for selectors, so an empty result is the same value each time (React subscribes by identity). */
export const NONE: never[] = [];

/** After undo or redo the frame being edited may be gone. */
function frameWithin(document: ProjectDocument, state: { boardId: string | null; frameIndex: number }) {
  const board = document.boards.find(item => item.id === state.boardId) ?? document.boards[0];
  const frameIndex = Math.min(state.frameIndex, (board?.frames.length ?? 1) - 1);
  return { boardId: board?.id ?? null, frameIndex, playhead: frameIndex, playing: false };
}

/** The active board, or null before a project is loaded. */
/** Stopped between two frames: the board shows the move, nothing is edited. */
export const isBetween = (state: { playing: boolean; playhead: number; frameIndex: number }) =>
  !state.playing && Math.abs(state.playhead - state.frameIndex) > 1e-6;

export function activeBoard(state: { document: ProjectDocument | null; boardId: string | null }): Board | null {
  return state.document?.boards.find(board => board.id === state.boardId) ?? state.document?.boards[0] ?? null;
}

/** The active frame's objects. */
export function activeObjects(state: { document: ProjectDocument | null; boardId: string | null; frameIndex: number }): TacticsObject[] {
  const board = activeBoard(state);
  return board?.frames[Math.min(state.frameIndex, board.frames.length - 1)]?.objects ?? NONE;
}
