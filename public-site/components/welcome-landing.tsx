import Link from "next/link";
import type { ReactNode } from "react";
import { PortalHero } from "./portal";

const appUrl = "https://app.teamzoneapp.se";

/** How the visitor arrived: from the follower account's confirmation link. */
export type Arrival = "confirmed" | "link_error" | null;

const features = [
  { title: "Kallelser och svar", text: "Kalla till träning och match, se vem som kommer och påminn den som inte svarat. Spelare och föräldrar svarar med ett tryck, även direkt i notisen på Android." },
  { title: "Närvaro", text: "Registrera närvaro efter aktiviteten, med sen ankomst och delvis närvaro. Närvaron följer spelaren över säsongen." },
  { title: "Inkorg för laget", text: "Lagchatt och ledarchatt skapas automatiskt. Skriv direkt till en spelare eller förälder, starta en grupp eller skicka ett utskick till hela laget." },
  { title: "Min assistent", text: "Påminner om obesvarade kallelser, närvaro som inte registrerats och matchresultat som saknas, så att inget faller mellan stolarna." },
  { title: "Klubbsajt och lagsidor", text: "Klubben får en egen publik sajt med nyheter, lag, matcher och resultat. Varje lag får en egen sida." },
  { title: "Nya spelare enkelt", text: "Dela en länk eller QR-kod så fyller nya spelare och föräldrar själva i sina kontaktuppgifter." },
];

const steps = [
  { title: "Skapa ett konto", text: "Logga in i appen med e-post och lösenord, eller med en kod som skickas till din e-post." },
  { title: "Skapa eller gå med i ett lag", text: "Skapa din klubb och ditt första lag, eller gå med i ett befintligt lag via inbjudan eller lagkod." },
  { title: "Kalla till första aktiviteten", text: "Lägg in träningar och matcher i kalendern och skicka kallelser. Svaren kommer direkt." },
];

/**
 * teamzoneapp.se for visitors who are not signed in: what TeamZone is, and
 * the two ways on: the app for people in a team, and the public pages (with
 * a follower account) for everyone who wants to follow a club or team.
 */
export function WelcomeLanding({ login, loading, error, arrival = null }: { login?: ReactNode; loading: boolean; error?: string; arrival?: Arrival }) {
  return <>
    {arrival && <div className={`pz-arrival${arrival === "link_error" ? " error" : ""}`} role={arrival === "link_error" ? "alert" : "status"}>
      <div className="cs-wrap">
        <p>
          <strong>{arrival === "confirmed" ? "Din e-postadress är bekräftad." : "Länken fungerade inte."}</strong>{" "}
          {arrival === "confirmed"
            ? "Ditt följarkonto är klart. Logga in för att börja följa lag och klubbar."
            : "Bekräftelselänken har gått ut eller redan använts. Logga in om du redan har bekräftat kontot, annars skapar du kontot igen."}
        </p>
        <a className="cs-button small" href="#folj">Logga in</a>
      </div>
    </div>}
    <PortalHero kicker="TeamZone · för föreningslivet" title="Laget på ett ställe" aside={<div className="pz-choices">
      <a className="pz-choice primary" href={appUrl}>
        <span className="cs-kicker">Är du med i ett lag?</span>
        <strong>Öppna appen</strong>
        <span>För ledare, spelare och föräldrar: kallelser, närvaro, kalender och meddelanden.</span>
      </a>
      <Link className="pz-choice" href="/klubbar">
        <span className="cs-kicker">Vill du följa ett lag?</span>
        <strong>Hitta klubb eller lag</strong>
        <span>Läs nyheter, matcher och resultat från klubbarnas publika sidor.</span>
      </Link>
    </div>}>
      <p className="pz-lead">Kallelser, närvaro, meddelanden och en egen klubbsajt. Byggt för ledare, spelare och föräldrar i föreningslivet.</p>
      <div className="cs-hero-actions">
        <a className="cs-button" href={appUrl}>Kom igång i appen</a>
        <a className="cs-button ghost" href="#folj">Logga in som följare</a>
      </div>
    </PortalHero>

    <section className="cs-section" aria-labelledby="welcome-features">
      <div className="cs-wrap">
        <div className="cs-section-head"><div><p className="cs-kicker">Det här gör TeamZone</p><h2 id="welcome-features">Mindre administration, mer fotboll</h2></div></div>
        <div className="pz-features six">
          {features.map((feature, index) => <article key={feature.title}>
            <span aria-hidden="true">{String(index + 1).padStart(2, "0")}</span>
            <h3>{feature.title}</h3><p>{feature.text}</p>
          </article>)}
        </div>
      </div>
    </section>

    <section className="cs-section alt" aria-labelledby="welcome-steps">
      <div className="cs-wrap">
        <div className="cs-section-head"><div><p className="cs-kicker">Kom igång</p><h2 id="welcome-steps">Tre steg till första kallelsen</h2></div></div>
        <ol className="pz-steps">
          {steps.map((step) => <li key={step.title}><h3>{step.title}</h3><p>{step.text}</p></li>)}
        </ol>
        <div className="cs-hero-actions pz-steps-action"><a className="cs-button" href={appUrl}>Öppna appen</a></div>
      </div>
    </section>

    <section className="cs-section" id="folj" aria-labelledby="welcome-follow">
      <div className="cs-wrap pz-follow">
        <div>
          <p className="cs-kicker">För supportrar, släkt och vänner</p>
          <h2 id="welcome-follow">Följ lag och klubbar</h2>
          <p className="pz-note dark">Med ett följarkonto samlas nyheter, matcher och slutresultat från lagen du följer på din egen startsida, på alla dina enheter. Vilka lag du följer är privat. Klubbarnas publika sidor kan alla läsa utan konto.</p>
          <div className="cs-hero-actions"><Link className="cs-button ghost dark" href="/klubbar">Sök klubbar och lag</Link></div>
          {loading && <p role="status" className="pz-note dark">Hämtar ditt konto…</p>}
          {error && <p role="alert" className="pz-error">{error}</p>}
        </div>
        {login}
      </div>
    </section>
  </>;
}
