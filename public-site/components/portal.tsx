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

export function PortalHeader({ active }: { active?: "home" | "search" | "legal" | "matchpool" }) {
  return (
    <header className="cs-header">
      <div className="cs-mainbar"><div className="cs-wrap">
        <Link href="/" className="cs-brand pz-brand"><span className="pz-mark" aria-hidden="true">TZ</span><span>TeamZone</span></Link>
        <nav className="cs-nav" aria-label="Huvudmeny">
          <Link href="/" aria-current={active === "home" ? "page" : undefined}>Start</Link>
          <Link href="/klubbar" aria-current={active === "search" ? "page" : undefined}>Hitta klubb</Link>
          <Link href="/matchpool" aria-current={active === "matchpool" ? "page" : undefined}>Matchpool</Link>
          {webtoolsUrl() && <a href={webtoolsUrl()!}>Webtools</a>}
          <a href="https://app.teamzoneapp.se">Öppna appen</a>
        </nav>
      </div></div>
    </header>
  );
}

export function PortalFooter() {
  return (
    <footer className="cs-footer">
      <div className="cs-wrap cs-footer-grid">
        <div className="cs-footer-club"><span className="pz-mark large" aria-hidden="true">TZ</span><div><strong>TeamZone</strong><span>Klubbar, lag och gemenskap</span></div></div>
        <div><h2>Upptäck</h2><ul><li><Link href="/klubbar">Hitta klubb eller lag</Link></li><li><Link href="/">Min startsida</Link></li><li><Link href="/matchpool">Matchpoolen</Link></li>{webtoolsUrl() && <li><a href={webtoolsUrl()!}>Webtools</a></li>}</ul></div>
        <div><h2>Konto</h2><ul><li><a href="https://app.teamzoneapp.se">Öppna TeamZone-appen</a></li><li><a href="https://app.teamzoneapp.se">Skapa konto</a></li></ul></div>
        <div><h2>Juridik</h2><ul><li><Link href="/integritet">Integritetspolicy</Link></li><li><Link href="/villkor">Användarvillkor</Link></li></ul></div>
      </div>
      <div className="cs-wrap cs-footer-base"><span>© {new Date().getFullYear()} TeamZone</span><span>Byggt för föreningslivet</span></div>
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
