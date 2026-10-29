import { notFound } from "next/navigation";
import { Suspense } from "react";
import { RequireAccount } from "../../../../components/shell";
import { FolderPage } from "../../../../components/tactics/FolderPage.tsx";

export const metadata = { title: "Tacticsboard" };

type Props = { params: Promise<{ id: string }> };

export default async function TacticsFolderPage({ params }: Props) {
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/.test(id)) notFound();
  return (
    <div className="wt-wrap wt-section bk-page">
      <p className="wt-kicker dark">Tacticsboard</p>
      <h1 className="wt-page-title">Mapp</h1>
      <Suspense fallback={<p className="wt-status">Laddar…</p>}>
        <RequireAccount returnTo={`/tacticsboard/mapp/${id}`}>
          <FolderPage id={id} />
        </RequireAccount>
      </Suspense>
    </div>
  );
}
