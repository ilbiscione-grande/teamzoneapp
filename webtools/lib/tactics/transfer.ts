// A project as a file: exported from the editor and imported on the start
// page as a new project of your own. The file is JSON: the format's name,
// its version, the project's name and kind, and the document; a bare
// document (boards and frames) is taken too, named after the file. What
// comes in is made whole as a saved document is (normalizeDocument);
// ties to TeamZone players do not come along, as the squad is another team's.
import { normalizeDocument } from "./document.ts";
import type { ProjectDocument, ProjectKind } from "./model.ts";

export const FILE_FORMAT = "teamzone-tacticsboard";
export const FILE_VERSION = 1;
/** As the server's limit on a project (core.tactics_projects). */
const MAX_BYTES = 4_000_000;
const kinds: ProjectKind[] = ["match", "training", "education"];

export type ProjectFile = { format: typeof FILE_FORMAT; version: number; name: string; kind: ProjectKind; document: ProjectDocument };
export type Imported = { name: string; kind: ProjectKind; document: ProjectDocument };

export function exportProject(name: string, kind: ProjectKind, document: ProjectDocument): string {
  const file: ProjectFile = { format: FILE_FORMAT, version: FILE_VERSION, name, kind, document };
  return JSON.stringify(file, null, 1);
}

/** A file name for the export: the project's name with only letters, digits and underscores. */
export const exportFileName = (name: string) => `${(name.trim() || "projekt").replace(/[^\p{L}\p{N}]+/gu, "_")}.tacticsboard.json`;

/** The project in a file's text, or why it cannot be imported. */
export function parseImport(text: string, fileName = "Importerat projekt"): Imported | { error: string } {
  if (text.length > MAX_BYTES) return { error: "Filen är för stor för ett projekt." };
  let raw: unknown;
  try { raw = JSON.parse(text); } catch { return { error: "Filen är inte ett Tacticsboard-projekt (ingen giltig JSON)." }; }
  if (!raw || typeof raw !== "object") return { error: "Filen är inte ett Tacticsboard-projekt." };
  const value = raw as Partial<ProjectFile> & Partial<ProjectDocument>;
  const wrapped = value.format === FILE_FORMAT;
  if (wrapped && (value.version ?? 0) > FILE_VERSION) return { error: "Filen kommer från en nyare version av Tacticsboard." };
  const source = (wrapped ? value.document : value) as Partial<ProjectDocument> | undefined;
  if (!source || !Array.isArray(source.boards) || source.boards.length === 0) return { error: "Filen har inga tavlor." };
  if (source.boards.some(board => !board || typeof board !== "object" || !Array.isArray(board.frames))) {
    return { error: "Filen är inte ett Tacticsboard-projekt (tavlorna saknar frames)." };
  }
  const document = normalizeDocument({ ...source, squad: [] });
  const players = (objects: ProjectDocument["boards"][number]["frames"][number]["objects"]) =>
    objects.map(item => item.type === "player" ? { ...item, personId: null } : item);
  const loose: ProjectDocument = {
    ...document,
    boards: document.boards.map(board => ({ ...board, frames: board.frames.map(frame => ({ ...frame, objects: players(frame.objects ?? []) })) })),
  };
  const name = (wrapped && typeof value.name === "string" && value.name.trim() ? value.name : fileName.replace(/(\.tacticsboard)?\.json$/i, ""))
    .trim().slice(0, 120) || "Importerat projekt";
  const kind = wrapped && kinds.includes(value.kind as ProjectKind) ? value.kind as ProjectKind : "match";
  return { name, kind, document: loose };
}
