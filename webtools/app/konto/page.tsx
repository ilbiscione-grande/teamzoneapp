import { AccountPage } from "../../components/account-page";

export const metadata = { title: "Konto" };

export default function KontoPage() {
  return (
    <div className="wt-wrap wt-section">
      <h1 className="wt-page-title">Konto</h1>
      <AccountPage />
    </div>
  );
}
