import { notFound } from "next/navigation";
import { Suspense } from "react";
import { RequireAccount } from "../../../../components/shell";
import { RequireTacticsboard } from "../../../../components/tactics/RequireTacticsboard.tsx";
import { FolderPage } from "../../../../components/tactics/FolderPage.tsx";
import { serverT } from "../../../../lib/i18n/server";

export const metadata = { title: "Tacticsboard" };

type Props = { params: Promise<{ id: string }> };

export default async function TacticsFolderPage({ params }: Props) {
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/.test(id)) notFound();
  const t = await serverT();
  return (
    <div className="wt-wrap wt-section bk-page">
      <p className="wt-kicker dark">Tacticsboard</p>
      <h1 className="wt-page-title">{t("Mapp")}</h1>
      <Suspense fallback={<p className="wt-status">{t("Laddar…")}</p>}>
        <RequireAccount returnTo={`/tacticsboard/mapp/${id}`}>
          <RequireTacticsboard><FolderPage id={id} /></RequireTacticsboard>
        </RequireAccount>
      </Suspense>
    </div>
  );
}
