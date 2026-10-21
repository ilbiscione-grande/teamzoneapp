import { Suspense } from "react";
import { RequireAccount } from "../../components/shell";
import { TournamentHome } from "../../components/tournament/tournament-home";

export const metadata = { title: "Turneringsplanerare" };

type Props = { searchParams: Promise<{ inbjudan?: string }> };

export default async function TournamentsPage({ searchParams }: Props) {
  const { inbjudan } = await searchParams;
  const returnTo = inbjudan && /^[0-9a-f]{64}$/.test(inbjudan) ? `/turneringar?inbjudan=${inbjudan}` : "/turneringar";
  return (
    <div className="wt-wrap wt-section bk-page">
      <p className="wt-kicker dark">Turneringsplanerare</p>
      <h1 className="wt-page-title">Turneringar</h1>
      <Suspense fallback={<p className="wt-status">Laddar…</p>}>
        <RequireAccount returnTo={returnTo}>
          <TournamentHome />
        </RequireAccount>
      </Suspense>
    </div>
  );
}
