import { notFound } from "next/navigation";
import { Suspense } from "react";
import { RequireAccount } from "../../../components/shell";
import { TournamentView } from "../../../components/tournament/tournament";

export const metadata = { title: "Turneringsplanerare" };

type Props = { params: Promise<{ id: string }> };

/** The tournament, and its registration link: the same page for everyone. */
export default async function TournamentPage({ params }: Props) {
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/.test(id)) notFound();
  return (
    <div className="wt-wrap wt-section bk-page">
      <Suspense fallback={<p className="wt-status">Laddar…</p>}>
        <RequireAccount returnTo={`/turneringar/${id}`}>
          <TournamentView id={id} />
        </RequireAccount>
      </Suspense>
    </div>
  );
}
