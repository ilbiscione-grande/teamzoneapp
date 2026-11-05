import { AccountPage } from "../../components/account-page";
import { serverT } from "../../lib/i18n/server";

export async function generateMetadata() {
  return { title: (await serverT())("Konto") };
}

export default async function KontoPage() {
  const t = await serverT();
  return (
    <div className="wt-wrap wt-section">
      <h1 className="wt-page-title">{t("Konto")}</h1>
      <AccountPage />
    </div>
  );
}
