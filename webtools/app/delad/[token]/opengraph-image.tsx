import { previewImage, PREVIEW_SIZE } from "../../../components/tactics/share-preview.tsx";
import { loadSharedTactics } from "../../../lib/tactics/shared.ts";

// The link's picture in a chat: the board as last saved.
export const size = PREVIEW_SIZE;
export const contentType = "image/png";
export const alt = "Tavlan";

export default async function Image({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  return previewImage(await loadSharedTactics(token));
}
