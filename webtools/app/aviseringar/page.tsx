import { NotificationsPage } from "../../components/notifications";

export const metadata = { title: "Aviseringar" };

export default function AviseringarPage() {
  return (
    <div className="wt-wrap wt-section wt-narrow-wide">
      <h1 className="wt-page-title">Aviseringar</h1>
      <NotificationsPage />
    </div>
  );
}
