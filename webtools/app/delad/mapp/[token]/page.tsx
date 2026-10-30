import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { SharedFolderPage } from "../../../../components/tactics/SharedFolderPage.tsx";
import { folderMetadata } from "../../../../components/tactics/share-preview.tsx";
import { loadSharedFolder } from "../../../../lib/tactics/shared.ts";

// Always the folder as it is now.
export const dynamic = "force-dynamic";

type Props = { params: Promise<{ token: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { token } = await params;
  return folderMetadata(await loadSharedFolder(token));
}

/** A shared Tacticsboard folder: its projects to open, without an account. */
export default async function SharedFolderRoute({ params }: Props) {
  const { token } = await params;
  const folder = await loadSharedFolder(token);
  if (!folder) notFound();
  return <SharedFolderPage token={token} folder={folder} />;
}
