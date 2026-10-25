// Tacticsboard's library (decision package 13): what you save from your
// boards. An exercise is one board with its details, a pass a training
// project's boards in order with theme and goal, a session an education
// project's boards in order. The boards go as in a template: no squad and no
// ties to TeamZone players. The details travel in the library as the server
// checks them (snake case); on a board they are ExerciseDetails.
import { boardsForTemplate } from "./templates.ts";
import type { AgeClass, Board, ExerciseDetails, ExercisePart, GameForm, GamePhase, ProjectKind } from "./model.ts";

export type LibraryKind = "exercise" | "plan" | "lesson";

export const libraryKindLabels: Record<LibraryKind, string> = { exercise: "Övning", plan: "Pass", lesson: "Session" };

export const partLabels: Record<ExercisePart, string> = { warmup: "Uppvärmning", main: "Huvuddel", finish: "Avslutning" };

/** The four phases with the ball, each beside its opposite without it. */
export const phaseLabels: Record<GamePhase, string> = {
  scoring: "Komma till avslut och göra mål",
  preventing_scoring: "Förhindra och rädda avslut",
  build_up: "Speluppbyggnad",
  preventing_build_up: "Förhindra speluppbyggnad",
  counter: "Kontring/omställning",
  regaining: "Återerövring av boll",
  attacking_play: "Anfallsspel",
  defending: "Försvarsspel",
};

export const ageClasses: AgeClass[] = ["7-9", "10-12", "13-15", "16+"];
export const ageClassLabels: Record<AgeClass, string> = { "7-9": "7–9 år", "10-12": "10–12 år", "13-15": "13–15 år", "16+": "16 år och äldre" };
export const gameForms: GameForm[] = ["3v3", "5v5", "7v7", "9v9", "11v11"];
export const gameFormLabels: Record<GameForm, string> = { "3v3": "3 mot 3", "5v5": "5 mot 5", "7v7": "7 mot 7", "9v9": "9 mot 9", "11v11": "11 mot 11" };

export const emptyExercise: ExerciseDetails = {
  part: "main", minutes: 15, players: null, area: "", coachingPoints: "", phase: null, ageClasses: [], gameForms: [],
};

/** What a kind of project can be saved as. */
export const libraryKindsFor: Record<ProjectKind, LibraryKind[]> = {
  training: ["exercise", "plan"],
  education: ["lesson"],
  // TBL-17: a match's boards are bound to the team and are not shared.
  match: [],
};

/** The project kind a library item starts a new project as. */
export const projectKindOf: Record<LibraryKind, ProjectKind> = { exercise: "training", plan: "training", lesson: "education" };

export type LibraryDetailsJson = {
  part?: ExercisePart;
  minutes?: number;
  players?: number | null;
  area?: string;
  organisation?: string;
  coaching_points?: string;
  phase?: GamePhase | null;
  age_classes?: AgeClass[];
  game_forms?: GameForm[];
};

/** A board's exercise details as the library keeps them; the organisation is the board's description. */
export function exerciseJson(board: Board): LibraryDetailsJson {
  const details = { ...emptyExercise, ...board.exercise };
  return {
    part: details.part,
    minutes: Math.round(Math.min(240, Math.max(0, details.minutes))),
    players: details.players == null ? null : Math.round(Math.min(60, Math.max(1, details.players))),
    area: details.area.slice(0, 40),
    organisation: (board.description ?? "").slice(0, 2000),
    coaching_points: details.coachingPoints.slice(0, 2000),
    phase: details.phase,
    age_classes: details.ageClasses,
    game_forms: details.gameForms,
  };
}

/** The library's details back on a board. */
export function exerciseFromJson(json: LibraryDetailsJson | undefined): ExerciseDetails {
  return {
    part: json?.part ?? "main",
    minutes: json?.minutes ?? emptyExercise.minutes,
    players: json?.players ?? null,
    area: json?.area ?? "",
    coachingPoints: json?.coaching_points ?? "",
    phase: json?.phase ?? null,
    ageClasses: json?.age_classes ?? [],
    gameForms: json?.game_forms ?? [],
  };
}

export type LibraryItemSummary = {
  id: string;
  kind: LibraryKind;
  title: string;
  details: LibraryDetailsJson & { theme?: string; goal?: string; exercises?: LibraryDetailsJson[] };
  version: number;
  source_project_id: string | null;
  source_board_id: string | null;
  board_count: number;
  boards: { id: string; name: string }[];
  /** Shared in TeamZone's library (step 2), or null. */
  shared?: LibraryShare;
  updated_at: string;
};

export type LibrarySave = { kind: LibraryKind; title: string; details: object; document: { schemaVersion: number; boards: Board[] } };

/** One board as an exercise. */
export function exerciseItem(board: Board, title: string): LibrarySave {
  const [clean] = boardsForTemplate([board], false);
  return { kind: "exercise", title, details: exerciseJson(board), document: { schemaVersion: 1, boards: [{ ...clean, exercise: undefined }] } };
}

/** A training project's boards in order as a pass, each with its exercise details. */
export function planItem(boards: Board[], title: string, theme: string, goal: string): LibrarySave {
  return {
    kind: "plan",
    title,
    details: { theme: theme.slice(0, 200), goal: goal.slice(0, 2000), exercises: boards.map(exerciseJson) },
    document: { schemaVersion: 1, boards: boardsForTemplate(boards, false).map(board => ({ ...board, exercise: undefined })) },
  };
}

/** An education project's boards in order as a session. */
export function lessonItem(boards: Board[], title: string): LibrarySave {
  return { kind: "lesson", title, details: {}, document: { schemaVersion: 1, boards: boardsForTemplate(boards, false) } };
}

/** A library item's boards to start a project from, with their exercise details back on them. */
export function boardsFromLibrary(item: Pick<LibraryItemSummary, "kind" | "details">, boards: Board[]): Board[] {
  return boards.map((board, index) => {
    const json = item.kind === "exercise" ? item.details : item.kind === "plan" ? item.details.exercises?.[index] : undefined;
    return json ? { ...board, exercise: exerciseFromJson(json) } : board;
  });
}

/** A short line about an item: its part, minutes, phase and boards. */
export function librarySummaryLine(item: Pick<LibraryItemSummary, "kind" | "details" | "board_count">): string {
  if (item.kind === "exercise") {
    return [
      item.details.part && partLabels[item.details.part],
      item.details.minutes != null && `${item.details.minutes} min`,
      item.details.phase && phaseLabels[item.details.phase],
    ].filter(Boolean).join(" · ");
  }
  if (item.kind === "plan") {
    const minutes = (item.details.exercises ?? []).reduce((sum, exercise) => sum + (exercise.minutes ?? 0), 0);
    return [item.details.theme, `${item.board_count} övningar`, minutes > 0 && `${minutes} min`].filter(Boolean).join(" · ");
  }
  return `${item.board_count} ${item.board_count === 1 ? "tavla" : "tavlor"}`;
}

/** An item of TeamZone's library: the writer by name, yours or TeamZone's own. */
export type SharedItemSummary = Omit<LibraryItemSummary, "source_project_id" | "source_board_id"> & {
  author: string;
  starter: boolean;
  mine: boolean;
  hidden: boolean;
};

/** Whether an item of your library is shared, and with its latest version. */
export type LibraryShare = { id: string; version: number; hidden: boolean; current: boolean } | null;

export type SharedFilters = { text: string; kind: LibraryKind | ""; part: ExercisePart | ""; phase: GamePhase | ""; age: AgeClass | ""; form: GameForm | "" };
export const noFilters: SharedFilters = { text: "", kind: "", part: "", phase: "", age: "", form: "" };
