import { Suspense } from "react";
import { RequireAccount } from "../../components/shell";
import { RequireTacticsboard } from "../../components/tactics/RequireTacticsboard.tsx";
import { TacticsboardEntry } from "../../components/tactics/TacticsboardEntry.tsx";
import { TacticsHome } from "../../components/tactics/TacticsHome.tsx";
import { TacticsProduct } from "../../components/tactics/TacticsProduct.tsx";

export const metadata = {
  title: "Tacticsboard",
  description: "Rita, animera och presentera taktik för träning, genomgångar och match. Prova gratis i 7 dagar.",
};

// Rebuilt hourly, so the launch offer leaves the page when it ends.
export const revalidate = 3600;

export default function TacticsboardPage() {
  return (
    <TacticsboardEntry product={<TacticsProduct />}>
      <div className="wt-wrap wt-section bk-page">
        <p className="wt-kicker dark">Tacticsboard</p>
        <h1 className="wt-page-title">Taktiktavla</h1>
        <Suspense fallback={<p className="wt-status">Laddar…</p>}>
          <RequireAccount returnTo="/tacticsboard">
            <RequireTacticsboard><TacticsHome /></RequireTacticsboard>
          </RequireAccount>
        </Suspense>
      </div>
    </TacticsboardEntry>
  );
}
