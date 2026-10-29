// Templates: ready boards for each kind of project (a match's lineup and set
// pieces, a training's exercises, a teaching material's principles), and
// your own boards saved as templates. A template carries no squad and no
// ties to TeamZone players; used, its boards get new ids so a project can
// hold the same template twice and share links stay apart.
import { applyFormation, createObject, newBoard, newFrame, newId } from "./document.ts";
import { formations } from "./formations.ts";
import { PITCH_LENGTH, PITCH_WIDTH, type Board, type PitchView, type Point, type ProjectDocument, type ProjectKind, type TacticsObject } from "./model.ts";

export type StarterBoard = { key: string; name: string; view: PitchView; ball?: Point; formation?: string };

const half = PITCH_LENGTH / 2;

/** The ready boards, per kind of project. The home team attacks to the right. */
export const starterSets: Record<ProjectKind, StarterBoard[]> = {
  match: [
    { key: "lineup", name: "Uppställning", view: "full", formation: "4-3-3", ball: { x: half, y: PITCH_WIDTH / 2 } },
    { key: "build-up", name: "Speluppbyggnad", view: "full" },
    { key: "attack", name: "Anfallsspel", view: "full" },
    { key: "defence", name: "Försvarsspel", view: "full" },
    { key: "corner-for", name: "Hörna anfall", view: "attack", ball: { x: PITCH_LENGTH - 0.6, y: 0.6 } },
    { key: "corner-against", name: "Hörna försvar", view: "defend", ball: { x: 0.6, y: 0.6 } },
    { key: "free-kick-for", name: "Frispark anfall", view: "attack", ball: { x: PITCH_LENGTH - 24, y: 26 } },
    { key: "free-kick-against", name: "Frispark försvar", view: "defend", ball: { x: 24, y: 26 } },
    { key: "throw-in-for", name: "Inkast anfall", view: "attack", ball: { x: PITCH_LENGTH - 22, y: 0 } },
    { key: "throw-in-against", name: "Inkast försvar", view: "defend", ball: { x: 22, y: 0 } },
  ],
  training: [
    { key: "warm-up", name: "Uppvärmning", view: "empty" },
    { key: "technique", name: "Teknik", view: "empty" },
    { key: "passing", name: "Passningsövning", view: "empty" },
    { key: "possession", name: "Possession", view: "empty" },
    { key: "finishing", name: "Avslut", view: "attack" },
    { key: "small-sided", name: "Smålagsspel", view: "empty" },
  ],
  education: [
    { key: "principle", name: "Princip", view: "full" },
    { key: "build-up", name: "Speluppbyggnad", view: "full" },
    { key: "pressing", name: "Press", view: "full" },
    { key: "transitions", name: "Omställningar", view: "full" },
    { key: "attacking-shape", name: "Anfallsspel", view: "full" },
    { key: "defensive-shape", name: "Försvarsspel", view: "full" },
  ],
};

/** The first ready board of each kind: what a project starts with when nothing is chosen. */
export const defaultStarterKeys: Record<ProjectKind, string[]> = { match: ["lineup"], training: ["warm-up"], education: ["principle"] };

/** A ready board, made: the view, and the ball and lineup when it has them. */
export function starterBoard(item: StarterBoard, homeName?: string, awayName?: string): Board {
  const board = { ...newBoard(item.name, homeName, awayName), view: item.view };
  let objects: TacticsObject[] = [];
  const lines = item.formation ? formations[item.formation] : undefined;
  if (lines) objects = applyFormation(objects, "home", lines);
  if (item.ball) objects = [...objects, createObject("ball", item.ball)];
  return { ...board, frames: [newFrame(objects)] };
}

/**
 * Boards to save as a template: no ties to TeamZone players, and without
 * the players' names unless they are kept. Numbers and positions stay.
 */
export function boardsForTemplate(boards: Board[], keepNames: boolean): Board[] {
  return boards.map(board => ({
    ...board,
    frames: board.frames.map(frame => ({
      ...frame,
      objects: frame.objects.map(item => item.type === "player"
        ? { ...item, personId: null, name: keepNames ? item.name : null }
        : item),
    })),
  }));
}

/** A template's boards put into a project: new ids for the boards and frames, the home team named as the project's. */
export function boardsFromTemplate(boards: Board[], homeName?: string): Board[] {
  return boards.map(board => ({
    ...newBoard(board.name ?? "Tavla"),
    ...board,
    id: newId(),
    teams: homeName ? { ...board.teams, home: { ...board.teams.home, name: homeName } } : board.teams,
    frames: (Array.isArray(board.frames) && board.frames.length > 0 ? board.frames : [newFrame()]).map(frame => ({ ...frame, id: newId() })),
  }));
}

/** A copy of a board in the same project, named as a copy. */
export function copyBoard(board: Board): Board {
  return { ...boardsFromTemplate([board])[0], name: `${board.name} (kopia)`.slice(0, 60) };
}

/** The project with a copy of one board put right after it, and the copy's id; unchanged (null) for an unknown board. */
export function duplicateBoard(document: ProjectDocument, boardId: string): { document: ProjectDocument; copyId: string | null } {
  const index = document.boards.findIndex(board => board.id === boardId);
  if (index < 0) return { document, copyId: null };
  const copy = copyBoard(document.boards[index]);
  const boards = [...document.boards];
  boards.splice(index + 1, 0, copy);
  return { document: { ...document, boards }, copyId: copy.id };
}

export type TemplateSummary = { id: string; name: string; kind: ProjectKind; boards: { id: string; name: string }[]; updated_at: string };
