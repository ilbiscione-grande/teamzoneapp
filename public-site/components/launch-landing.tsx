import { PortalFooter, PortalHeader, PortalHero, portalClass, webtoolsUrl } from "./portal";
import { features } from "./welcome-landing";

// teamzoneapp.se while Tacticsboard is the one thing on sale: fixed text with
// no database behind it, what TeamZone is, and the way on to Tacticsboard.

const tacticsboardPoints = [
  { title: "Rita", text: "Spelare, bollar, koner, mål, pilar och ytor på en riktig plan." },
  { title: "Animera", text: "Bygg förloppet steg för steg och spela upp det." },
  { title: "Presentera", text: "Visa tavlan i helskärm, eller håll en livegenomgång där laget följer med i mobilen." },
  { title: "Dela", text: "Skicka en länk till spelare och föräldrar. De behöver inget konto för att titta." },
];

export function LaunchLanding() {
  const tacticsboard = `${webtoolsUrl() ?? "https://webtools.teamzoneapp.se"}/tacticsboard`;
  return (
    <main className={portalClass}>
      <PortalHeader active="home" />
      <PortalHero kicker="TeamZone · för föreningslivet" title="Laget på ett ställe" aside={<div className="pz-choices">
        <a className="pz-choice primary" href={tacticsboard}>
          <span className="cs-kicker">Tillgänglig nu</span>
          <strong>Tacticsboard</strong>
          <span>Rita, animera och presentera taktik. Prova gratis i 7 dagar.</span>
        </a>
        <div className="pz-choice pz-choice-coming">
          <span className="cs-kicker">Kommer snart</span>
          <strong>TeamZone-appen</strong>
          <span>Kallelser, närvaro, meddelanden och en egen klubbsajt.</span>
        </div>
      </div>}>
        <p className="pz-lead">Verktyg för ledare, spelare och föräldrar i föreningslivet. Börja med Tacticsboard redan i dag.</p>
        <div className="cs-hero-actions"><a className="cs-button" href={tacticsboard}>Prova Tacticsboard gratis</a></div>
      </PortalHero>

      <section className="cs-section" aria-labelledby="launch-tacticsboard">
        <div className="cs-wrap">
          <div className="cs-section-head"><div><p className="cs-kicker">Tillgänglig nu</p><h2 id="launch-tacticsboard">Tacticsboard</h2></div></div>
          <img className="pz-launch-shot" src="https://webtools.teamzoneapp.se/tacticsboard/editor.png" width={1521} height={1045}
            alt="Tacticsboard med en taktiktavla, verktyg och tidslinje." loading="lazy" />
          <div className="pz-features">
            {tacticsboardPoints.map((point, index) => <article key={point.title}>
              <span aria-hidden="true">{String(index + 1).padStart(2, "0")}</span>
              <h3>{point.title}</h3><p>{point.text}</p>
            </article>)}
          </div>
          <div className="cs-hero-actions pz-steps-action"><a className="cs-button" href={tacticsboard}>Prova gratis i 7 dagar</a></div>
        </div>
      </section>

      <section className="cs-section alt" aria-labelledby="launch-app">
        <div className="cs-wrap">
          <div className="cs-section-head"><div><p className="cs-kicker">Kommer snart</p><h2 id="launch-app">TeamZone-appen</h2></div></div>
          <div className="pz-features six">
            {features.map((feature, index) => <article key={feature.title}>
              <span aria-hidden="true">{String(index + 1).padStart(2, "0")}</span>
              <h3>{feature.title}</h3><p>{feature.text}</p>
            </article>)}
          </div>
        </div>
      </section>
      <PortalFooter />
    </main>
  );
}
