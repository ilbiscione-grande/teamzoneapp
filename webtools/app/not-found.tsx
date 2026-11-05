import Link from "next/link";
import { serverT } from "../lib/i18n/server";

export default async function NotFound() {
  const t = await serverT();
  return (
    <div className="wt-wrap wt-section wt-narrow">
      <h1 className="wt-page-title">{t("Sidan finns inte")}</h1>
      <p>{t("Adressen leder inte till någon sida i Webtools.")}</p>
      <Link className="wt-link" href="/">{t("Till alla appar")}</Link>
    </div>
  );
}
