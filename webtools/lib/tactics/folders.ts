// Tacticsboard's folders (core.tactics_folders): projects that belong
// together, such as the parts of a game idea. A project is linked into a
// folder, not moved: the same project may be in several folders, and the
// folder keeps its projects in the order the owner sets.
import { translator, type Translate } from "../i18n/translate.ts";
import type { ProjectSummary } from "./model.ts";

const same: Translate = translator("sv");

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
export function joinNames(names: string[], t: Translate = same): string {
  if (names.length <= 1) return names[0] ?? "";
  return t("{first} och {last}", { first: names.slice(0, -1).join(", "), last: names[names.length - 1] });
}

/** What removing a project says about the folders it is in; empty when in none. */
export function removalNote(folders: FolderRef[], t: Translate = same): string {
  if (folders.length === 0) return "";
  const names = joinNames(folders.map(folder => folder.name), t);
  return folders.length === 1 ? t(" Det tas också bort ur mappen {names}.", { names }) : t(" Det tas också bort ur mapparna {names}.", { names });
}

/** The folders a project ends up in when one is ticked or unticked. */
export function toggleFolder(ids: string[], id: string, on: boolean): string[] {
  return on ? (ids.includes(id) ? ids : [...ids, id]) : ids.filter(item => item !== id);
}

/** The person's message for a folder RPC's error. */
export function folderErrorText(message: string, fallback: string, t: Translate = same): string {
  if (message.includes("too_many_folders")) return t("Du har redan 200 mappar. Ta bort någon först.");
  if (message.includes("too_many_projects")) return t("En mapp rymmer högst 100 projekt.");
  return fallback;
}
