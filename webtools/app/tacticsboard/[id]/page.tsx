import { notFound } from "next/navigation";
import { Suspense } from "react";
import { RequireAccount } from "../../../components/shell";
import { TacticsEditor } from "../../../components/tactics/TacticsEditor.tsx";

export const metadata = { title: "Tacticsboard" };

type Props = { params: Promise<{ id: string }> };

export default async function TacticsProjectPage({ params }: Props) {
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/.test(id)) notFound();
  return (
    <Suspense fallback={<p className="wt-status">Laddar…</p>}>
      <RequireAccount returnTo={`/tacticsboard/${id}`}>
        <TacticsEditor id={id} />
      </RequireAccount>
    </Suspense>
  );
}
