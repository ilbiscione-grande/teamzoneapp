// Making and changing the document without touching it in place: a new
// project, board or object, a board's current objects and the edits the
// editor makes. Pure, so the store and the tests share them.
import { settleBalls } from "./ball.ts";
import { formationPositions } from "./formations.ts";
import {
  PITCH_LENGTH, PITCH_WIDTH, SCHEMA_VERSION,
  type Board, type Easing, type Effect, type EquipmentKind, type Frame, type ObjectType, type PlayerObject, type Point,
  type ProjectDocument, type Side, type SquadPlayer, type TacticsObject,
} from "./model.ts";
import { effectsOf } from "./timeline.ts";

export const newId = () =>
  typeof crypto !== "undefined" && "randomUUID" in crypto
    ? crypto.randomUUID()
    : `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;

export const teamColors: Record<Side, { color: string; numberColor: string }> = {
  home: { color: "#1d4ed8", numberColor: "#ffffff" },
  away: { color: "#dc2626", numberColor: "#ffffff" },
};

export function newFrame(objects: TacticsObject[] = []): Frame {
  return { id: newId(), objects, durationMs: 1500, note: "" };
}

export function newBoard(name: string, homeName = "Hemma", awayName = "Borta"): Board {
  return {
    id: newId(),
    name,
    view: "full",
    overlay: "none",
    showNames: true,
    showPositions: false,
    teams: {
      home: { name: homeName, ...teamColors.home },
      away: { name: awayName, ...teamColors.away },
    },
    frames: [newFrame()],
  };
}

export function newDocument(boardName = "Tavla 1", homeName?: string): ProjectDocument {
  return { schemaVersion: SCHEMA_VERSION, boards: [newBoard(boardName, homeName)], squad: [] };
}

/** A document read from the server, made whole: missing parts get defaults. */
export function normalizeDocument(value: unknown): ProjectDocument {
  const raw = (value && typeof value === "object" ? value : {}) as Partial<ProjectDocument>;
  const boards = Array.isArray(raw.boards) && raw.boards.length > 0 ? raw.boards : newDocument().boards;
  return {
    schemaVersion: SCHEMA_VERSION,
    squad: Array.isArray(raw.squad) ? raw.squad : [],
    ...(raw.branding && typeof raw.branding === "object" ? { branding: raw.branding } : {}),
    boards: boards.map(board => ({
      ...newBoard(board.name ?? "Tavla"),
      ...board,
      frames: Array.isArray(board.frames) && board.frames.length > 0 ? board.frames : [newFrame()],
    })),
  };
}

const base = (point: Point) => ({ id: newId(), x: point.x, y: point.y, rotation: 0, locked: false, hidden: false });

/** The next free number for a side, from 1. */
export function nextNumber(objects: TacticsObject[], side: Side): number {
  const taken = new Set(objects.filter((item): item is PlayerObject => item.type === "player" && item.side === side).map(item => item.number));
  let number = 1;
  while (taken.has(number)) number++;
  return number;
}

export function createPlayer(point: Point, side: Side, objects: TacticsObject[], from?: SquadPlayer): PlayerObject {
  return {
    ...base(point), type: "player", side,
    number: from ? from.number : nextNumber(objects, side),
    name: from?.name ?? null, position: from?.position ?? null, personId: from?.personId ?? null, color: null,
  };
}

/** A new object of a placeable kind at a point. */
export function createObject(type: Exclude<ObjectType, "player" | "line" | "freehand" | "rect" | "ellipse" | "chain">, point: Point): TacticsObject {
  if (type === "ball") return { ...base(point), type: "ball", attachedTo: null, offset: null };
  if (type === "text") return { ...base(point), type: "text", text: "Text", size: 2.2, color: "#ffffff", background: true };
  const colors: Record<EquipmentKind, string> = { cone: "#f97316", pole: "#facc15", mannequin: "#1e293b", goal: "#ffffff" };
  return { ...base(point), type, color: colors[type], scale: 1 };
}

const kindNames: Record<ObjectType, string> = {
  player: "Spelare", ball: "Boll", cone: "Kon", pole: "Pinne", mannequin: "Docka", goal: "Mål",
  line: "Linje", freehand: "Frihand", rect: "Rektangel", ellipse: "Ellips", text: "Text", chain: "Linje mellan spelare",
};

/** The object as the object list names it. */
export function objectLabel(item: TacticsObject, board: Board): string {
  if (item.label) return item.label;
  if (item.type === "player") {
    const team = board.teams[item.side].name;
    return [item.number !== null ? `#${item.number}` : null, item.name ?? team, item.position ? `(${item.position})` : null].filter(Boolean).join(" ");
  }
  if (item.type === "line") return item.arrow === "none" ? "Linje" : item.dashed ? "Löpning" : "Pil";
  if (item.type === "text") return `Text: ${item.text.slice(0, 24)}`;
  if (item.type === "chain") return item.closed ? "Yta mellan spelare" : "Linje mellan spelare";
  return kindNames[item.type];
}

export function kindName(type: ObjectType): string {
  return kindNames[type];
}

/** The document with one board's frame changed; the balls follow. */
export function updateFrame(
  document: ProjectDocument, boardId: string, frameIndex: number,
  change: (objects: TacticsObject[]) => TacticsObject[],
): ProjectDocument {
  return {
    ...document,
    boards: document.boards.map(board => board.id !== boardId ? board : {
      ...board,
      frames: board.frames.map((frame, index) => index !== frameIndex ? frame : { ...frame, objects: settleBalls(change(frame.objects)) }),
    }),
  };
}

export function updateBoard(document: ProjectDocument, boardId: string, change: (board: Board) => Board): ProjectDocument {
  return { ...document, boards: document.boards.map(board => board.id === boardId ? change(board) : board) };
}

export type Stacking = "up" | "down" | "top" | "bottom";

/**
 * Moves the chosen objects together in the drawing order, keeping their own
 * order: a step up (drawn later, on top), a step down, or all the way to the
 * top or the bottom. Unchanged (the same list) when they cannot go further.
 */
export function stack(objects: TacticsObject[], ids: string[], where: Stacking): TacticsObject[] {
  const chosen = new Set(ids);
  if (!objects.some(item => chosen.has(item.id))) return objects;
  let next: TacticsObject[];
  if (where === "top" || where === "bottom") {
    const moved = objects.filter(item => chosen.has(item.id)), rest = objects.filter(item => !chosen.has(item.id));
    next = where === "top" ? [...rest, ...moved] : [...moved, ...rest];
  } else {
    next = [...objects];
    const up = where === "up";
    // From the end it moves towards, so a block of chosen objects moves as one.
    for (let index = up ? next.length - 2 : 1; up ? index >= 0 : index < next.length; index += up ? -1 : 1) {
      const target = index + (up ? 1 : -1);
      if (chosen.has(next[index].id) && !chosen.has(next[target].id)) [next[index], next[target]] = [next[target], next[index]];
    }
  }
  return next.every((item, index) => item === objects[index]) ? objects : next;
}

/** Puts an object at a place in the drawing order (0 at the bottom): dragged there in the object list. */
export function moveTo(objects: TacticsObject[], id: string, place: number): TacticsObject[] {
  const item = objects.find(other => other.id === id);
  if (!item) return objects;
  const rest = objects.filter(other => other.id !== id);
  const at = Math.max(0, Math.min(rest.length, place));
  const next = [...rest.slice(0, at), item, ...rest.slice(at)];
  return next.every((other, index) => other === objects[index]) ? objects : next;
}

/** Patches objects by id; a patch is shallow, keyed by object. */
export function patchObjects(objects: TacticsObject[], patches: Record<string, Partial<TacticsObject>>): TacticsObject[] {
  return objects.map(item => patches[item.id] ? ({ ...item, ...patches[item.id] } as TacticsObject) : item);
}

/** Moves objects one step forward (drawn later, on top) or back. */
export function restack(objects: TacticsObject[], id: string, step: 1 | -1): TacticsObject[] {
  const index = objects.findIndex(item => item.id === id);
  const target = index + step;
  if (index < 0 || target < 0 || target >= objects.length) return objects;
  const next = [...objects];
  [next[index], next[target]] = [next[target], next[index]];
  return next;
}

/** A side's players placed in a formation: existing players move, missing ones are added. */
export function applyFormation(objects: TacticsObject[], side: Side, lines: number[], squad: SquadPlayer[] = []): TacticsObject[] {
  const spots = formationPositions(lines, side);
  const players = objects.filter((item): item is PlayerObject => item.type === "player" && item.side === side && !item.hidden);
  const moved = new Map<string, Point>();
  players.slice(0, spots.length).forEach((player, index) => moved.set(player.id, spots[index]));
  let next = objects.map(item => moved.has(item.id) ? { ...item, ...moved.get(item.id)! } : item);
  // Squad players not yet on the board fill the remaining places.
  const placed = new Set(players.map(player => player.personId).filter(Boolean));
  const unplaced = squad.filter(player => !placed.has(player.personId));
  for (const spot of spots.slice(players.length)) {
    next = [...next, createPlayer(spot, side, next, unplaced.shift())];
  }
  return next;
}

/** Clamps a point to the grass around the pitch. */
export function keepOnGrass(point: Point, margin = 6): Point {
  return {
    x: Math.min(PITCH_LENGTH + margin, Math.max(-margin, point.x)),
    y: Math.min(PITCH_WIDTH + margin, Math.max(-margin, point.y)),
  };
}


/** A copy of a frame put after it: the same objects (same ids, so they move between the two), no effects, bends or lofted passes of its own. */
export function insertFrame(board: Board, afterIndex: number): Board {
  const source = board.frames[afterIndex] ?? board.frames[board.frames.length - 1];
  const copy: Frame = {
    ...newFrame(source.objects.map(item => ({ ...item, effect: null, effects: [], pathControl: null, ...(item.type === "ball" ? { flight: undefined } : {}) }) as TacticsObject)),
    durationMs: source.durationMs,
    ...(source.easing ? { easing: source.easing } : {}),
  };
  const frames = [...board.frames];
  frames.splice(afterIndex + 1, 0, copy);
  return { ...board, frames };
}

export function removeFrame(board: Board, index: number): Board {
  if (board.frames.length < 2) return board;
  return { ...board, frames: board.frames.filter((_, i) => i !== index) };
}

export function moveFrame(board: Board, index: number, step: 1 | -1): Board {
  const target = index + step;
  if (target < 0 || target >= board.frames.length) return board;
  const frames = [...board.frames];
  [frames[index], frames[target]] = [frames[target], frames[index]];
  return { ...board, frames };
}

export function setFrameDuration(board: Board, index: number, durationMs: number): Board {
  return { ...board, frames: board.frames.map((frame, i) => i === index ? { ...frame, durationMs: Math.min(10000, Math.max(200, durationMs)) } : frame) };
}

export function setFrameEasing(board: Board, index: number, easing: Easing): Board {
  return { ...board, frames: board.frames.map((frame, i) => i === index ? { ...frame, easing } : frame) };
}

/** An object's effects with one added or taken away, as a patch; a board's single old effect becomes the list. */
export function toggleEffect(item: TacticsObject, kind: Effect, on: boolean): Partial<TacticsObject> {
  const current = effectsOf(item);
  const effects = on ? (current.includes(kind) ? current : [...current, kind]) : current.filter(other => other !== kind);
  return { effects, effect: null };
}
