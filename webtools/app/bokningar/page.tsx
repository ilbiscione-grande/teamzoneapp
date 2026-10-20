import { Suspense } from "react";
import { BookingHome } from "../../components/booking/booking-home";
import { RequireAccount } from "../../components/shell";

export const metadata = { title: "Bokningshanterare" };

type Props = { searchParams: Promise<{ inbjudan?: string }> };

export default async function BookingsPage({ searchParams }: Props) {
  const { inbjudan } = await searchParams;
  const returnTo = inbjudan && /^[0-9a-f]{64}$/.test(inbjudan) ? `/bokningar?inbjudan=${inbjudan}` : "/bokningar";
  return (
    <div className="wt-wrap wt-section bk-page">
      <p className="wt-kicker dark">Bokningshanterare</p>
      <h1 className="wt-page-title">Bokningar</h1>
      <Suspense fallback={<p className="wt-status">Laddar…</p>}>
        <RequireAccount returnTo={returnTo}>
          <BookingHome />
        </RequireAccount>
      </Suspense>
    </div>
  );
}
