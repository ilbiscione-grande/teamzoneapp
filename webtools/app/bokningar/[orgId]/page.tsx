import { notFound } from "next/navigation";
import { Suspense } from "react";
import { BookingOrganization } from "../../../components/booking/organization";
import { RequireAccount } from "../../../components/shell";

export const metadata = { title: "Bokningshanterare" };

type Props = { params: Promise<{ orgId: string }>; searchParams: Promise<Record<string, string | undefined>> };

export default async function OrganizationPage({ params, searchParams }: Props) {
  const { orgId } = await params;
  if (!/^[0-9a-f-]{36}$/.test(orgId)) notFound();
  // From the app's "Boka resurs": the booking form survives signing in.
  const query = await searchParams;
  const fromApp = query.boka === "1" && query.aktivitet
    ? `?boka=1${query.lag ? `&lag=${query.lag}` : ""}&aktivitet=${query.aktivitet}` : "";
  return (
    <div className="wt-wrap wt-section bk-page">
      <Suspense fallback={<p className="wt-status">Laddar…</p>}>
        <RequireAccount returnTo={`/bokningar/${orgId}${fromApp}`}>
          <BookingOrganization id={orgId} />
        </RequireAccount>
      </Suspense>
    </div>
  );
}
