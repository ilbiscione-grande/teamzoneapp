// Projects dragged from the start page onto a folder: their ids in the
// drag's data under a type of their own, so a folder takes nothing else.
export const DRAGGED_PROJECTS = "application/x-tacticsboard-projects";

/** Puts the dragged projects in the drag, with their names as plain text. */
export function startProjectDrag(transfer: DataTransfer, ids: string[], names: string[]) {
  transfer.setData(DRAGGED_PROJECTS, JSON.stringify(ids));
  transfer.setData("text/plain", names.join(", "));
  transfer.effectAllowed = "copy";
}

/** The dragged projects' ids, or none when something else is dropped. */
export function draggedProjects(transfer: DataTransfer): string[] {
  try {
    const ids = JSON.parse(transfer.getData(DRAGGED_PROJECTS) || "[]");
    return Array.isArray(ids) ? ids.filter((id): id is string => typeof id === "string") : [];
  } catch {
    return [];
  }
}
