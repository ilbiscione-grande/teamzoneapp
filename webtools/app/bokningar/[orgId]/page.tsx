import { notFound } from "next/navigation";
import { BookingOrganization } from "../../../components/booking/organization";
import { RequireAccount } from "../../../components/shell";

export const metadata = { title: "Bokningshanterare" };

type Props = { params: Promise<{ orgId: string }> };

export default async function OrganizationPage({ params }: Props) {
  const { orgId } = await params;
  if (!/^[0-9a-f-]{36}$/.test(orgId)) notFound();
  return (
    <div className="wt-wrap wt-section bk-page">
      <RequireAccount returnTo={`/bokningar/${orgId}`}>
        <BookingOrganization id={orgId} />
      </RequireAccount>
    </div>
  );
}
