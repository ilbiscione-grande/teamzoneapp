import Link from "next/link";
import type { ReactNode } from "react";
import { clubSiteFonts } from "./club-site";

// TeamZone's own pages (start page, sign-in, personal start page, search and
// status pages) in the same look as the club and team pages.
export const portalClass = `cs ${clubSiteFonts}`;

/** TeamZone Webtools; hidden until its address is configured. */
export function webtoolsUrl(): string | null {
  // NEXT_PUBLIC_: set at build, the same on the server and in the browser.
  const value = process.env.NEXT_PUBLIC_WEBTOOLS_URL;
  return value && /^https:\/\/[a-z0-9.-]+$/.test(value) ? value : null;
}

/** Tacticsboard is on sale and the app is not: only fixed pages are linked. */
export function tacticsboardLaunch(): boolean {
  return process.env.NEXT_PUBLIC_TACTICSBOARD_LAUNCH === "1";
}

export type Locale = "sv" | "en";

/** The way to the site in English; shown when Tacticsboard opens in English. */
export function englishOpen(): boolean {
  return process.env.NEXT_PUBLIC_TACTICSBOARD_ENGLISH === "on";
}

const portalText = {
  sv: { home: "/", tagline: "Klubbar, lag och gemenskap", discover: "Upptäck", start: "Start", legal: "Juridik", privacy: ["/integritet", "Integritetspolicy"], terms: ["/villkor", "Användarvillkor"], built: "Byggt för föreningslivet" },
  en: { home: "/en", tagline: "Clubs, teams and community", discover: "Discover", start: "Home", legal: "Legal", privacy: ["/en/privacy", "Privacy policy"], terms: ["/en/terms", "Terms of use"], built: "Built for grassroots sport" },
} as const;

export function PortalHeader({ active, locale = "sv" }: { active?: "home" | "search" | "legal" | "matchpool"; locale?: Locale }) {
  const text = portalText[locale];
  return (
    <header className="cs-header">
      <div className="cs-mainbar"><div className="cs-wrap">
        <Link href={text.home} className="cs-brand pz-brand"><span className="pz-mark" aria-hidden="true">TZ</span><span>TeamZone</span></Link>
        <nav className="cs-nav" aria-label={locale === "en" ? "Main menu" : "Huvudmeny"}>
          <Link href={text.home} aria-current={active === "home" ? "page" : undefined}>{text.start}</Link>
          {!tacticsboardLaunch() && <Link href="/klubbar" aria-current={active === "search" ? "page" : undefined}>Hitta klubb</Link>}
          {!tacticsboardLaunch() && <Link href="/matchpool" aria-current={active === "matchpool" ? "page" : undefined}>Matchpool</Link>}
          {webtoolsUrl() && <a href={webtoolsUrl()!}>Webtools</a>}
          {!tacticsboardLaunch() && <a href="https://app.teamzoneapp.se">Öppna appen</a>}
        </nav>
      </div></div>
    </header>
  );
}

export function PortalFooter({ locale = "sv" }: { locale?: Locale }) {
  const text = portalText[locale];
  const other = locale === "en" || englishOpen();
  return (
    <footer className="cs-footer">
      <div className="cs-wrap cs-footer-grid">
        <div className="cs-footer-club"><span className="pz-mark large" aria-hidden="true">TZ</span><div><strong>TeamZone</strong><span>{text.tagline}</span></div></div>
        <div><h2>{text.discover}</h2><ul>{!tacticsboardLaunch() && <li><Link href="/klubbar">Hitta klubb eller lag</Link></li>}<li><Link href={text.home}>{tacticsboardLaunch() ? text.start : "Min startsida"}</Link></li>{!tacticsboardLaunch() && <li><Link href="/matchpool">Matchpoolen</Link></li>}{webtoolsUrl() && <li><a href={webtoolsUrl()!}>Webtools</a></li>}</ul></div>
        {!tacticsboardLaunch() && <div><h2>Konto</h2><ul><li><a href="https://app.teamzoneapp.se">Öppna TeamZone-appen</a></li><li><a href="https://app.teamzoneapp.se">Skapa konto</a></li></ul></div>}
        <div><h2>{text.legal}</h2><ul><li><Link href={text.privacy[0]}>{text.privacy[1]}</Link></li><li><Link href={text.terms[0]}>{text.terms[1]}</Link></li>{other && <li><Link href={locale === "en" ? "/" : "/en"} lang={locale === "en" ? "sv" : "en"}>{locale === "en" ? "På svenska" : "In English"}</Link></li>}</ul></div>
      </div>
      <div className="cs-wrap cs-footer-base"><span>© {new Date().getFullYear()} TeamZone</span><span>{text.built}</span></div>
    </footer>
  );
}

/** A dark page-top band with kicker, title and optional text and actions. */
export function PortalHero({ kicker, title, children, mark = "TZ", aside }: { kicker: string; title: string; children?: ReactNode; mark?: string; aside?: ReactNode }) {
  return (
    <section className="cs-hero pz-hero">
      <span className="cs-hero-mark" aria-hidden="true">{mark}</span>
      <div className={`cs-wrap pz-hero-grid${aside ? " with-aside" : ""}`}>
        <div className="cs-hero-text"><p className="cs-kicker">{kicker}</p><h1>{title}</h1>{children}</div>
        {aside}
      </div>
    </section>
  );
}
