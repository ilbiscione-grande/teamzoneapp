import { AppCard } from "../components/app-card";
import { Welcome } from "../components/welcome";
import { webtoolApps } from "../lib/apps";

export default function HomePage() {
  return (
    <>
      <section className="wt-hero">
        <div className="wt-wrap">
          <p className="wt-kicker">TeamZone Webtools</p>
          <h1>Verktyg för lag och klubbar</h1>
          <p className="wt-lead">
            Fristående appar för tränare, ledare och klubbar. Varje app fungerar för sig, och med ditt
            TeamZone-konto hänger de ihop med dina lag när du vill.
          </p>
          <Welcome />
        </div>
      </section>
      <section className="wt-wrap wt-section" aria-labelledby="apps-title">
        <h2 id="apps-title">Appar</h2>
        <div className="wt-grid">
          {webtoolApps.map(app => <AppCard key={app.slug} app={app} />)}
        </div>
      </section>
      <section className="wt-wrap wt-section wt-points" aria-label="Så fungerar Webtools">
        <article><h3>Ett konto</h3><p>Samma inloggning i alla appar. Har du inget konto skapar du ett här.</p></article>
        <article><h3>Fristående</h3><p>Apparna går att använda utan att du är kopplad till ett lag eller en klubb.</p></article>
        <article><h3>Abonnemang</h3><p>Du betalar per app och kan säga upp när du vill.</p></article>
      </section>
    </>
  );
}
