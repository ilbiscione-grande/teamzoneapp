import { Suspense } from "react";
import { RequireAccount } from "../../components/shell";
import { RequireTacticsboard } from "../../components/tactics/RequireTacticsboard.tsx";
import { TacticsboardEntry } from "../../components/tactics/TacticsboardEntry.tsx";
import { TacticsHome } from "../../components/tactics/TacticsHome.tsx";
import { TacticsProduct } from "../../components/tactics/TacticsProduct.tsx";
import { serverT } from "../../lib/i18n/server";

export async function generateMetadata() {
  const t = await serverT();
  return { title: "Tacticsboard", description: t("Rita, animera och presentera taktik för träning, genomgångar och match. Prova gratis i 7 dagar."), robots: { index: true, follow: true } };
}

// Rebuilt hourly, so the launch offer leaves the page when it ends.
export const revalidate = 3600;

export default async function TacticsboardPage() {
  const t = await serverT();
  return (
    <TacticsboardEntry product={<TacticsProduct />}>
      <div className="wt-wrap wt-section bk-page">
        <p className="wt-kicker dark">Tacticsboard</p>
        <h1 className="wt-page-title">{t("Taktiktavla")}</h1>
        <Suspense fallback={<p className="wt-status">{t("Laddar…")}</p>}>
          <RequireAccount returnTo="/tacticsboard">
            <RequireTacticsboard><TacticsHome /></RequireTacticsboard>
          </RequireAccount>
        </Suspense>
      </div>
    </TacticsboardEntry>
  );
}
