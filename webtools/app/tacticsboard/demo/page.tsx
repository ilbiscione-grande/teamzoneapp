import { notFound } from "next/navigation";
import { TacticsDemo } from "../../../components/tactics/TacticsDemo.tsx";

export const metadata = { title: "Tacticsboard (demo)" };

// Read when served, not built in.
export const dynamic = "force-dynamic";

/** For development only (or a local production run with TACTICS_DEMO=1): the editor on a local board, nothing saved. */
export default function TacticsDemoPage() {
  if (process.env.NODE_ENV === "production" && process.env.TACTICS_DEMO !== "1") notFound();
  return <TacticsDemo />;
}
