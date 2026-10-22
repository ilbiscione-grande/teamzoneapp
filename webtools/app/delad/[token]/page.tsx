import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { SharedViewer } from "../../../components/tactics/SharedViewer.tsx";
import { loadSharedTactics } from "../../../lib/tactics/shared.ts";

// Always the board as last saved.
export const dynamic = "force-dynamic";

type Props = { params: Promise<{ token: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { token } = await params;
  const shared = await loadSharedTactics(token);
  return { title: shared?.name ?? "Delad tavla" };
}

/** A shared Tacticsboard project or board: watched and played without an account. */
export default async function SharedTacticsPage({ params }: Props) {
  const { token } = await params;
  const shared = await loadSharedTactics(token);
  if (!shared) notFound();
  return <SharedViewer shared={shared} />;
}
