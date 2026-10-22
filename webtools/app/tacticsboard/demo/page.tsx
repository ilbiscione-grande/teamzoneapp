import { notFound } from "next/navigation";
import { TacticsDemo } from "../../../components/tactics/TacticsDemo.tsx";

export const metadata = { title: "Tacticsboard (demo)" };

/** For development only: the editor on a local board, nothing saved. */
export default function TacticsDemoPage() {
  if (process.env.NODE_ENV === "production") notFound();
  return <TacticsDemo />;
}
