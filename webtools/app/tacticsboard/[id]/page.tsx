import { notFound } from "next/navigation";
import { Suspense } from "react";
import { RequireAccount } from "../../../components/shell";
import { RequireTacticsboard } from "../../../components/tactics/RequireTacticsboard.tsx";
import { TacticsEditor } from "../../../components/tactics/TacticsEditor.tsx";
import { serverT } from "../../../lib/i18n/server";

export const metadata = { title: "Tacticsboard" };

type Props = { params: Promise<{ id: string }> };

export default async function TacticsProjectPage({ params }: Props) {
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/.test(id)) notFound();
  const t = await serverT();
  return (
    <Suspense fallback={<p className="wt-status">{t("Laddar…")}</p>}>
      <RequireAccount returnTo={`/tacticsboard/${id}`}>
        <RequireTacticsboard note={false} lockedFrame>
          <TacticsEditor id={id} />
        </RequireTacticsboard>
      </RequireAccount>
    </Suspense>
  );
}
