// The start page's search (components/tactics/home): the filters, and the
// team's projects found by words and kind here, as they carry nothing more;
// and the details a new project may start with.
import { emptyExercise } from "./library.ts";
import type { AgeClass, Board, ExercisePart, GameForm, GamePhase, ProjectKind } from "./model.ts";

export type HomeFilters = { text: string; kind: ProjectKind | ""; part: ExercisePart | ""; phase: GamePhase | ""; age: AgeClass | ""; form: GameForm | "" };
export const noHomeFilters: HomeFilters = { text: "", kind: "", part: "", phase: "", age: "", form: "" };

export type TeamProjectText = { name: string; kind: ProjectKind; team_name: string | null; owner_name?: string | null };

/** The team's projects that match the words and kind; they carry no other details to filter on. */
export function teamMatches(project: TeamProjectText, filters: HomeFilters): boolean {
  if (filters.part || filters.phase || filters.age || filters.form) return false;
  if (filters.kind && project.kind !== filters.kind) return false;
  const words = filters.text.trim().toLowerCase().split(/\s+/).filter(Boolean);
  const text = [project.name, project.team_name, project.owner_name].filter(Boolean).join(" ").toLowerCase();
  return words.every(word => text.includes(word));
}


/** What a new project may be told about itself at once; all optional. */
export type NewProjectDetails = { phase: GamePhase | ""; ageClasses: AgeClass[]; gameForms: GameForm[] };
export const noDetails: NewProjectDetails = { phase: "", ageClasses: [], gameForms: [] };

/**
 * The new project's boards with its details, for the library's filters to
 * find (they read each board's exercise). A board keeps its own part, else
 * the one its ready board names; nothing told, the boards stay as they are.
 */
export function withDetails(boards: Board[], details: NewProjectDetails, parts: (ExercisePart | undefined)[] = []): Board[] {
  if (!details.phase && details.ageClasses.length === 0 && details.gameForms.length === 0) return boards;
  return boards.map((board, index) => {
    const own = board.exercise ?? { ...emptyExercise, part: parts[index] ?? emptyExercise.part };
    return {
      ...board,
      exercise: {
        ...own,
        phase: details.phase || own.phase,
        ageClasses: details.ageClasses.length > 0 ? details.ageClasses : own.ageClasses,
        gameForms: details.gameForms.length > 0 ? details.gameForms : own.gameForms,
      },
    };
  });
}
