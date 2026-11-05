import { LiveJoin } from "../../components/tactics/live/LiveJoin.tsx";
import { serverT } from "../../lib/i18n/server";

export async function generateMetadata() {
  return { title: (await serverT())("Livelektion") };
}

/** Joining a live lesson by typing its code. */
export default function LivePage() {
  return <LiveJoin initialCode={null} />;
}
