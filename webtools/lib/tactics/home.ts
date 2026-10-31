// The start page's search (components/tactics/home): the filters, and the
// team's projects found by words and kind here, as they carry nothing more.
import type { AgeClass, ExercisePart, GameForm, GamePhase, ProjectKind } from "./model.ts";

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

