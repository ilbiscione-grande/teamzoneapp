import { launchText } from "./launch-text";
import { PortalFooter, PortalHeader, PortalHero, portalClass, webtoolsUrl, type Locale } from "./portal";

// teamzoneapp.se while Tacticsboard is the one thing on sale: fixed text with
// no database behind it, what TeamZone is, and the way on to Tacticsboard.

export function LaunchLanding({ locale = "sv" }: { locale?: Locale }) {
  const text = launchText[locale];
  const tacticsboard = `${webtoolsUrl() ?? "https://webtools.teamzoneapp.se"}/tacticsboard`;
  return (
    <main className={portalClass} lang={locale}>
      <PortalHeader active="home" locale={locale} />
      <PortalHero kicker={text.kicker} title={text.title} aside={<div className="pz-choices">
        <a className="pz-choice primary" href={tacticsboard}>
          <span className="cs-kicker">{text.availableNow}</span>
          <strong>Tacticsboard</strong>
          <span>{text.choice}</span>
        </a>
        <div className="pz-choice pz-choice-coming">
          <span className="cs-kicker">{text.comingSoon}</span>
          <strong>{text.app}</strong>
          <span>{text.appChoice}</span>
        </div>
      </div>}>
        <p className="pz-lead">{text.lead}</p>
        <div className="cs-hero-actions"><a className="cs-button" href={tacticsboard}>{text.tryBoard}</a></div>
      </PortalHero>

      <section className="cs-section" aria-labelledby="launch-tacticsboard">
        <div className="cs-wrap">
          <div className="cs-section-head"><div><p className="cs-kicker">{text.availableNow}</p><h2 id="launch-tacticsboard">Tacticsboard</h2></div></div>
          <img className="pz-launch-shot" src={`https://webtools.teamzoneapp.se/tacticsboard/${text.shot}`} width={1521} height={1045}
            alt={text.shotAlt} loading="lazy" />
          <div className="pz-features">
            {text.points.map((point, index) => <article key={point.title}>
              <span aria-hidden="true">{String(index + 1).padStart(2, "0")}</span>
              <h3>{point.title}</h3><p>{point.text}</p>
            </article>)}
          </div>
          <div className="cs-hero-actions pz-steps-action"><a className="cs-button" href={tacticsboard}>{text.tryFree}</a></div>
        </div>
      </section>

      <section className="cs-section alt" aria-labelledby="launch-app">
        <div className="cs-wrap">
          <div className="cs-section-head"><div><p className="cs-kicker">{text.comingSoon}</p><h2 id="launch-app">{text.app}</h2></div></div>
          <div className="pz-features six">
            {text.features.map((feature, index) => <article key={feature.title}>
              <span aria-hidden="true">{String(index + 1).padStart(2, "0")}</span>
              <h3>{feature.title}</h3><p>{feature.text}</p>
            </article>)}
          </div>
        </div>
      </section>
      <PortalFooter locale={locale} />
    </main>
  );
}
