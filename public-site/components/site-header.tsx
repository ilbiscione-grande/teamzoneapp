import Link from "next/link";

export function SiteHeader({ clubName, clubHref }: { clubName?: string; clubHref?: string }) {
  return (
    <header className="topbar">
      <Link href="/" className="brand-link"><span className="brand-mark">TZ</span> TeamZone</Link>
      {clubName && clubHref ? <Link className="club-crumb" href={clubHref}>{clubName}</Link> : <span className="privacy-label">Endast uttryckligen publicerad information</span>}
    </header>
  );
}
