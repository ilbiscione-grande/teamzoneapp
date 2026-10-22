import { LiveJoin } from "../../components/tactics/live/LiveJoin.tsx";

export const metadata = { title: "Livelektion" };

/** Joining a live lesson by typing its code. */
export default function LivePage() {
  return <LiveJoin initialCode={null} />;
}
