import { LiveJoin } from "../../../components/tactics/live/LiveJoin.tsx";
import { serverT } from "../../../lib/i18n/server";
import { normalizeCode } from "../../../lib/tactics/live.ts";

export async function generateMetadata() {
  return { title: (await serverT())("Livelektion") };
}

type Props = { params: Promise<{ code: string }> };

/** A live lesson's link or QR code: the code is filled in. */
export default async function LiveCodePage({ params }: Props) {
  const { code } = await params;
  return <LiveJoin initialCode={normalizeCode(code)} />;
}
