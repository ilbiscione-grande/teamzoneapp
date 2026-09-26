import Link from "next/link";

export function SiteHeader({ clubName, clubHref }: { clubName?: string; clubHref?: string }) {
  return (
    <header className="topbar">
      <Link href="/" className="brand-link"><span className="brand-mark">TZ</span> TeamZone</Link>
      <nav className="header-links" aria-label="Huvudmeny">{clubName && clubHref && <Link className="club-crumb" href={clubHref}>{clubName}</Link>}<Link href="/">Min startsida</Link><Link href="/klubbar">Sök</Link></nav>
    </header>
  );
}
