import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { SharedViewer } from "../../../../../components/tactics/SharedViewer.tsx";
import { sharedMetadata } from "../../../../../components/tactics/share-preview.tsx";
import { loadSharedFolderProject } from "../../../../../lib/tactics/shared.ts";

// Always the board as last saved.
export const dynamic = "force-dynamic";

type Props = { params: Promise<{ token: string; project: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { token, project } = await params;
  return sharedMetadata(await loadSharedFolderProject(token, project));
}

/** A project seen through a shared folder: watched and played, with the way back to the folder. */
export default async function SharedFolderProjectRoute({ params }: Props) {
  const { token, project } = await params;
  const shared = await loadSharedFolderProject(token, project);
  if (!shared) notFound();
  return <SharedViewer shared={shared} back={{ href: `/delad/mapp/${token}`, label: `Till ${shared.folder_name ?? "mappen"}` }} />;
}
