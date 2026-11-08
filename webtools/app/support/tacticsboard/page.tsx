import { HelpIndex } from "../../../components/tactics/help/HelpIndex.tsx";
import { serverLocale } from "../../../lib/i18n/server";

// Tacticsboard's help: questions on account, payment and technique, and the
// guides. Open to everyone, signed in or not, and to search engines.
export async function generateMetadata() {
  const english = (await serverLocale()) === "en";
  return {
    title: english ? "Help · Tacticsboard" : "Hjälp · Tacticsboard",
    description: english
      ? "Answers on account, payment and technique, and guides to everything Tacticsboard can do."
      : "Svar om konto, betalning och teknik, och guider till allt Tacticsboard kan.",
    robots: { index: true, follow: true },
  };
}

export default async function HelpPage() {
  const locale = await serverLocale();
  return (
    <div className="wt-wrap wt-section bk-page">
      <p className="wt-kicker dark">Tacticsboard</p>
      <h1 className="wt-page-title">{locale === "en" ? "Help" : "Hjälp"}</h1>
      <HelpIndex locale={locale} />
    </div>
  );
}
