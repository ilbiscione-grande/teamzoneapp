"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useState } from "react";
import { useAccount } from "./account";
import { NotificationBell } from "./notifications";

export function Header() {
  const { session, links, signOut } = useAccount();
  const path = usePathname();
  const router = useRouter();
  return (
    <header className="wt-header">
      <div className="wt-wrap wt-header-row">
        <Link href="/" className="wt-brand" aria-label="TeamZone Webtools, start">
          <span className="wt-mark" aria-hidden="true">TZ</span>
          <span>Webtools</span>
        </Link>
        <nav className="wt-nav" aria-label="Huvudmeny">
          <Link href="/" aria-current={path === "/" ? "page" : undefined}>Appar</Link>
          {session ? (
            <>
              <Link href="/konto" aria-current={path === "/konto" ? "page" : undefined}>Konto</Link>
              <button type="button" className="wt-nav-button" onClick={async () => { await signOut(); router.push("/"); }}>Logga ut</button>
            </>
          ) : (
            <Link href={`/logga-in?returnTo=${encodeURIComponent(path ?? "/")}`} aria-current={path === "/logga-in" ? "page" : undefined}>Logga in</Link>
          )}
          <NotificationBell />
          <a href={links.siteUrl} className="wt-nav-out">teamzoneapp.se</a>
        </nav>
      </div>
    </header>
  );
}

export function Footer() {
  const { links } = useAccount();
  return (
    <footer className="wt-footer">
      <div className="wt-wrap wt-footer-row">
        <div className="wt-footer-brand"><span className="wt-mark" aria-hidden="true">TZ</span><div><strong>TeamZone Webtools</strong><span>Verktyg för lag och klubbar</span></div></div>
        <ul>
          <li><a href={links.siteUrl}>teamzoneapp.se</a></li>
          <li><a href={links.appUrl}>TeamZone-appen</a></li>
          <li><a href={`${links.siteUrl}/integritet`}>Integritetspolicy</a></li>
          <li><a href={`${links.siteUrl}/villkor`}>Användarvillkor</a></li>
        </ul>
      </div>
    </footer>
  );
}

/** First sign-in: the account's terms, accepted once for all of TeamZone. */
export function LegalStep() {
  const { legal, acceptLegal } = useAccount();
  const [checked, setChecked] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  if (!legal) return null;
  return (
    <section className="wt-panel wt-legal" aria-labelledby="legal-title">
      <h2 id="legal-title">Godkänn villkoren</h2>
      <p>Ditt TeamZone-konto behöver godkänna de aktuella villkoren innan du använder Webtools. De gäller hela TeamZone.</p>
      <label className="wt-check">
        <input type="checkbox" checked={checked} onChange={event => setChecked(event.target.checked)} />
        <span>Jag godkänner <a href={legal.terms_url} target="_blank" rel="noreferrer">användarvillkoren</a> och har läst <a href={legal.privacy_url} target="_blank" rel="noreferrer">integritetspolicyn</a>.</span>
      </label>
      {error && <p role="alert" className="wt-error">{error}</p>}
      <button type="button" className="wt-button" disabled={!checked || busy} onClick={async () => {
        setBusy(true);
        setError((await acceptLegal()) ?? "");
        setBusy(false);
      }}>Godkänn och fortsätt</button>
    </section>
  );
}

/** Pages for signed-in accounts: sign-in first, then the terms. */
export function RequireAccount({ returnTo, children }: { returnTo: string; children: React.ReactNode }) {
  const { ready, available, session, legal, accepted, error } = useAccount();
  if (!ready || (session && !legal && !error)) return <p className="wt-status">Laddar…</p>;
  if (!available) return <p className="wt-status" role="alert">Inloggningen är inte tillgänglig just nu. Försök igen senare.</p>;
  if (!session) {
    return (
      <section className="wt-panel">
        <h2>Logga in med ditt TeamZone-konto</h2>
        <p>Webtools använder samma konto som TeamZone-appen. Du behöver inte vara kopplad till något lag eller någon klubb.</p>
        <Link className="wt-button" href={`/logga-in?returnTo=${encodeURIComponent(returnTo)}`}>Logga in eller skapa konto</Link>
      </section>
    );
  }
  if (error) return <p className="wt-status" role="alert">{error}</p>;
  if (!accepted) return <LegalStep />;
  return <>{children}</>;
}
