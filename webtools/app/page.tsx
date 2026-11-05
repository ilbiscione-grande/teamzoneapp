import { AppCard } from "../components/app-card";
import { Welcome } from "../components/welcome";
import { webtoolApps } from "../lib/apps";
import { serverT } from "../lib/i18n/server";
import { tacticsboardOnly } from "../lib/site-scope";

export default async function HomePage() {
  const t = await serverT();
  const onlyTacticsboard = tacticsboardOnly();
  return (
    <>
      <section className="wt-hero">
        <div className="wt-wrap">
          <p className="wt-kicker">TeamZone Webtools</p>
          <h1>{t("Verktyg för lag och klubbar")}</h1>
          <p className="wt-lead">
            {onlyTacticsboard
              ? t("Börja med Tacticsboard. Fler appar för tränare, ledare och klubbar är på väg.")
              : t("Fristående appar för tränare, ledare och klubbar. Varje app fungerar för sig, och med ditt TeamZone-konto hänger de ihop med dina lag när du vill.")}
          </p>
          <Welcome />
        </div>
      </section>
      <section className="wt-wrap wt-section" aria-labelledby="apps-title">
        <h2 id="apps-title">{t("Appar")}</h2>
        <div className="wt-grid">
          {webtoolApps.map(app => <AppCard key={app.slug} app={app} tacticsboardOnly={onlyTacticsboard} />)}
        </div>
      </section>
      <section className="wt-wrap wt-section wt-points" aria-label={t("Så fungerar Webtools")}>
        <article><h3>{t("Ett konto")}</h3><p>{t("Samma inloggning i alla appar. Har du inget konto skapar du ett här.")}</p></article>
        <article><h3>{t("Fristående")}</h3><p>{t("Apparna går att använda utan att du är kopplad till ett lag eller en klubb.")}</p></article>
        <article><h3>{t("Abonnemang")}</h3><p>{t("Du betalar per app och kan säga upp när du vill.")}</p></article>
      </section>
    </>
  );
}
