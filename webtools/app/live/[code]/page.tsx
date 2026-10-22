import { LiveJoin } from "../../../components/tactics/live/LiveJoin.tsx";
import { normalizeCode } from "../../../lib/tactics/live.ts";

export const metadata = { title: "Livelektion" };

type Props = { params: Promise<{ code: string }> };

/** A live lesson's link or QR code: the code is filled in. */
export default async function LiveCodePage({ params }: Props) {
  const { code } = await params;
  return <LiveJoin initialCode={normalizeCode(code)} />;
}
