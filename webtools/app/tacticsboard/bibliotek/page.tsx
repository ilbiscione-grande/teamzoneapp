import { Suspense } from "react";
import { RequireAccount } from "../../../components/shell";
import { RequireTacticsboard } from "../../../components/tactics/RequireTacticsboard.tsx";
import { SharedLibrary } from "../../../components/tactics/SharedLibrary.tsx";
import { serverT } from "../../../lib/i18n/server";

export async function generateMetadata() {
  return { title: `${(await serverT())("Biblioteket")} · Tacticsboard` };
}

export default async function SharedLibraryPage() {
  const t = await serverT();
  return (
    <div className="wt-wrap wt-section bk-page">
      <p className="wt-kicker dark">Tacticsboard</p>
      <h1 className="wt-page-title">{t("Biblioteket")}</h1>
      <Suspense fallback={<p className="wt-status">{t("Laddar…")}</p>}>
        <RequireAccount returnTo="/tacticsboard/bibliotek">
          <RequireTacticsboard><SharedLibrary /></RequireTacticsboard>
        </RequireAccount>
      </Suspense>
    </div>
  );
}
