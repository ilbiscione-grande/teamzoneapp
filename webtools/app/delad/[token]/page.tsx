import type { Metadata } from "next";
import { SharedGone } from "../../../components/tactics/SharedGone.tsx";
import { SharedViewer } from "../../../components/tactics/SharedViewer.tsx";
import { sharedMetadata } from "../../../components/tactics/share-preview.tsx";
import { loadSharedTactics } from "../../../lib/tactics/shared.ts";

// Always the board as last saved.
export const dynamic = "force-dynamic";

type Props = { params: Promise<{ token: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { token } = await params;
  return sharedMetadata(await loadSharedTactics(token));
}

/** A shared Tacticsboard project or board: watched and played without an account. */
export default async function SharedTacticsPage({ params }: Props) {
  const { token } = await params;
  const shared = await loadSharedTactics(token);
  // Said on the page itself: a run-out link from TeamZone is the usual case, not a wrong address.
  if (!shared) return <SharedGone />;
  return <SharedViewer shared={shared} />;
}
