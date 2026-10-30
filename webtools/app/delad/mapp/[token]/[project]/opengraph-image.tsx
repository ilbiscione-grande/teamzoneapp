import { previewImage, PREVIEW_SIZE } from "../../../../../components/tactics/share-preview.tsx";
import { loadSharedFolderProject } from "../../../../../lib/tactics/shared.ts";

// The link's picture in a chat: the project's first board as last saved.
export const size = PREVIEW_SIZE;
export const contentType = "image/png";
export const alt = "Tavlan";

export default async function Image({ params }: { params: Promise<{ token: string; project: string }> }) {
  const { token, project } = await params;
  return previewImage(await loadSharedFolderProject(token, project));
}
