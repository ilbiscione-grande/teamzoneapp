// Tacticsboard's folders (core.tactics_folders): projects that belong
// together, such as the parts of a game idea. A project is linked into a
// folder, not moved: the same project may be in several folders, and the
// folder keeps its projects in the order the owner sets.
import type { ProjectSummary } from "./model.ts";

export type FolderRef = { id: string; name: string };
export type FolderSummary = FolderRef & { description: string; project_count: number; created_at: string; updated_at: string };
export type Folder = FolderSummary & { projects: ProjectSummary[] };

/** The ids in a new order, the one at index moved a step up (-1) or down (1); unchanged at an end. */
export function moveInOrder(ids: string[], index: number, step: -1 | 1): string[] {
  const target = index + step;
  if (index < 0 || index >= ids.length || target < 0 || target >= ids.length) return ids;
  const next = [...ids];
  [next[index], next[target]] = [next[target], next[index]];
  return next;
}

/** "Spelidé 2026", "Spelidé 2026 och Spelidé 2027", "A, B och C". */
export function joinNames(names: string[]): string {
  if (names.length <= 1) return names[0] ?? "";
  return `${names.slice(0, -1).join(", ")} och ${names[names.length - 1]}`;
}

/** What removing a project says about the folders it is in; empty when in none. */
export function removalNote(folders: FolderRef[]): string {
  if (folders.length === 0) return "";
  return ` Det tas också bort ur ${folders.length === 1 ? "mappen" : "mapparna"} ${joinNames(folders.map(folder => folder.name))}.`;
}

/** The folders a project ends up in when one is ticked or unticked. */
export function toggleFolder(ids: string[], id: string, on: boolean): string[] {
  return on ? (ids.includes(id) ? ids : [...ids, id]) : ids.filter(item => item !== id);
}

/** The person's message for a folder RPC's error. */
export function folderErrorText(message: string, fallback: string): string {
  if (message.includes("too_many_folders")) return "Du har redan 200 mappar. Ta bort någon först.";
  if (message.includes("too_many_projects")) return "En mapp rymmer högst 100 projekt.";
  return fallback;
}
