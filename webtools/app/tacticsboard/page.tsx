import { Suspense } from "react";
import { RequireAccount } from "../../components/shell";
import { RequireTacticsboard } from "../../components/tactics/RequireTacticsboard.tsx";
import { TacticsHome } from "../../components/tactics/TacticsHome.tsx";

export const metadata = { title: "Tacticsboard" };

export default function TacticsboardPage() {
  return (
    <div className="wt-wrap wt-section bk-page">
      <p className="wt-kicker dark">Tacticsboard</p>
      <h1 className="wt-page-title">Taktiktavla</h1>
      <Suspense fallback={<p className="wt-status">Laddar…</p>}>
        <RequireAccount returnTo="/tacticsboard">
          <RequireTacticsboard><TacticsHome /></RequireTacticsboard>
        </RequireAccount>
      </Suspense>
    </div>
  );
}
