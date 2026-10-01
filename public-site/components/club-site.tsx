import Link from "next/link";
import { Barlow_Condensed, Inter } from "next/font/google";
import type { ReactNode } from "react";
import { clubThemeHref } from "../lib/club-theme";

// Club and team pages: a club-site look (dark header and hero, condensed
// display type, match cards) shared by the club page, its team channels and
// its news articles.
const display = Barlow_Condensed({ subsets: ["latin"], weight: ["600", "700", "800"], variable: "--cs-display", display: "swap" });
const body = Inter({ subsets: ["latin"], variable: "--cs-body", display: "swap" });
export const clubSiteFonts = `${display.variable} ${body.variable}`;

const timeZone = "Europe/Stockholm";

/** Class names for a club-site page; the club's colours, if any, come from a linked stylesheet. */
export function clubSiteClass(club: { primary_color?: string | null; accent_color?: string | null }) {
  const themed = clubThemeHref(club.primary_color, club.accent_color) !== null;
  return `cs ${clubSiteFonts}${themed ? " cs-theme" : ""}`;
}

export function ClubTheme({ club }: { club: { primary_color?: string | null; accent_color?: string | null } }) {
  const href = clubThemeHref(club.primary_color, club.accent_color);
  return href ? <link rel="stylesheet" href={href} precedence="club-theme" /> : null;
}

export type NewsItem = { id: string; slug?: string; title: string; summary?: string; published_at: string; media_path?: string | null };
export type CalendarEvent = { id: string; title: string; starts_at: string; event_type: string; location_name?: string; team_name?: string; team_slug?: string };
export type ResultItem = { id: string; title: string; starts_at: string; score_us: number; score_opponent: number; report_text?: string | null };

export function Crest({ name, src, size = "md" }: { name: string; src?: string | null; size?: "sm" | "md" | "lg" }) {
  if (src) return <img className={`cs-crest cs-crest-${size}`} src={src} alt={`${name}s klubbmärke`} />;
  return <span className={`cs-crest cs-crest-${size} cs-crest-initials`} aria-hidden="true">{initials(name)}</span>;
}

export function ClubHeader({ clubName, clubHref, crest, children }: { clubName: string; clubHref: string; crest?: string | null; children: ReactNode }) {
  return (
    <header className="cs-header">
      <div className="cs-utility"><div className="cs-wrap"><Link href="/" className="cs-utility-brand"><span className="cs-tz">TZ</span> TeamZone</Link><nav aria-label="TeamZone"><Link href="/">Min startsida</Link><Link href="/klubbar">Hitta klubb</Link></nav></div></div>
      <div className="cs-mainbar"><div className="cs-wrap">
        <Link href={clubHref} className="cs-brand"><Crest name={clubName} src={crest} size="sm" /><span>{clubName}</span></Link>
        <nav className="cs-nav">{children}</nav>
      </div></div>
    </header>
  );
}

export function ClubFooter({ clubName, clubHref, crest, locality, teams }: { clubName: string; clubHref: string; crest?: string | null; locality?: string; teams?: { id: string; slug: string; name: string }[] }) {
  return (
    <footer className="cs-footer">
      <div className="cs-wrap cs-footer-grid">
        <div className="cs-footer-club"><Crest name={clubName} src={crest} size="md" /><div><strong>{clubName}</strong>{locality && <span>{locality}</span>}</div></div>
        {teams && teams.length > 0 && <div><h2>Lag</h2><ul>{teams.slice(0, 8).map(team => <li key={team.id}><Link href={`${clubHref}/${team.slug}`}>{team.name}</Link></li>)}</ul></div>}
        <div><h2>Klubben</h2><ul><li><Link href={`${clubHref}#nyheter`}>Nyheter</Link></li><li><Link href={`${clubHref}#handelser`}>Kalender</Link></li><li><Link href={`${clubHref}#kontakt`}>Kontakt</Link></li></ul></div>
        <div><h2>TeamZone</h2><ul><li><Link href="/klubbar">Hitta klubb</Link></li><li><Link href="/integritet">Integritet</Link></li><li><Link href="/villkor">Villkor</Link></li></ul></div>
      </div>
      <div className="cs-wrap cs-footer-base"><span>© {new Date().getFullYear()} {clubName}</span><span>Klubbsidan drivs med <Link href="/">TeamZone</Link></span></div>
    </footer>
  );
}

export function SectionHead({ title, kicker, href, linkText }: { title: string; kicker?: string; href?: string; linkText?: string }) {
  return <div className="cs-section-head"><div>{kicker && <p className="cs-kicker">{kicker}</p>}<h2>{title}</h2></div>{href && <a href={href} className="cs-more">{linkText ?? "Visa alla"} <span aria-hidden="true">→</span></a>}</div>;
}

export function NewsGrid({ items, clubSlug, clubName, crest }: { items: NewsItem[]; clubSlug: string; clubName: string; crest?: string | null }) {
  const [first, ...rest] = items;
  return (
    <div className="cs-news">
      <NewsCard item={first} clubSlug={clubSlug} clubName={clubName} crest={crest} featured />
      {rest.map(item => <NewsCard key={item.id} item={item} clubSlug={clubSlug} clubName={clubName} crest={crest} />)}
    </div>
  );
}

function NewsCard({ item, clubSlug, clubName, crest, featured = false }: { item: NewsItem; clubSlug: string; clubName: string; crest?: string | null; featured?: boolean }) {
  const href = item.slug ? `/${clubSlug}/nyheter/${item.slug}` : undefined;
  const body = (
    <>
      <div className="cs-news-media">{item.media_path ? <img src={item.media_path} alt="" /> : <div className="cs-news-placeholder"><Crest name={clubName} src={crest} size="md" /></div>}<span className="cs-tag">Nyhet</span></div>
      <div className="cs-news-body"><h3>{item.title}</h3>{featured && item.summary && <p>{item.summary}</p>}<div className="cs-news-meta"><time dateTime={item.published_at}>{formatDate(item.published_at)}</time>{href && <span aria-hidden="true">→</span>}</div></div>
    </>
  );
  return <article className={`cs-news-card${featured ? " featured" : ""}${href ? "" : " plain"}`}>{href ? <Link href={href}>{body}</Link> : body}</article>;
}

export function DateBlock({ value }: { value: string }) {
  const date = new Date(value);
  return (
    <time className="cs-date" dateTime={value}>
      <strong>{part(date, { day: "numeric" })}</strong>
      <span>{part(date, { month: "short" }).replace(".", "")}<small>{part(date, { weekday: "short" }).replace(".", "")}</small></span>
    </time>
  );
}

export function EventCard({ event, teamHref, hero = false }: { event: CalendarEvent; teamHref?: string; hero?: boolean }) {
  return (
    <article className={`cs-event${hero ? " hero" : ""}`}>
      <div className="cs-event-top"><DateBlock value={event.starts_at} /><span className={`cs-type ${event.event_type}`}>{eventLabel(event.event_type)}</span></div>
      <h3>{event.title}</h3>
      <div className="cs-event-info">
        <span className="cs-time">{formatTime(event.starts_at)}</span>
        {event.location_name && <span>{event.location_name}</span>}
        {event.team_name && (teamHref ? <Link href={teamHref}>{event.team_name}</Link> : <span>{event.team_name}</span>)}
      </div>
    </article>
  );
}

export function ResultCard({ result, teamName, children }: { result: ResultItem; teamName: string; children?: ReactNode }) {
  const outcome = result.score_us > result.score_opponent ? "win" : result.score_us < result.score_opponent ? "loss" : "draw";
  return (
    <article className="cs-result">
      <div className="cs-result-top"><time dateTime={result.starts_at}>{formatDate(result.starts_at)}</time><span className={`cs-outcome ${outcome}`}>{outcome === "win" ? "Vinst" : outcome === "loss" ? "Förlust" : "Oavgjort"}</span></div>
      <h3>{result.title}</h3>
      <div className="cs-score"><span>{teamName}</span><strong>{result.score_us}<i>–</i>{result.score_opponent}</strong><span>Motståndare</span></div>
      {children}
    </article>
  );
}

export function Empty({ text }: { text: string }) { return <div className="cs-empty">{text}</div>; }

export function eventLabel(type: string) { return ({ match: "Match", training: "Träning", meeting: "Möte", activity: "Aktivitet" } as Record<string, string>)[type] ?? "Händelse"; }
export function formatDate(value: string) { return new Intl.DateTimeFormat("sv-SE", { dateStyle: "medium", timeZone }).format(new Date(value)); }
export function formatTime(value: string) { return new Intl.DateTimeFormat("sv-SE", { timeStyle: "short", timeZone }).format(new Date(value)); }
function part(date: Date, options: Intl.DateTimeFormatOptions) { return new Intl.DateTimeFormat("sv-SE", { ...options, timeZone }).format(date); }
export function initials(name: string) { return name.split(/\s+/).filter(Boolean).slice(0, 2).map(word => word[0]?.toUpperCase() ?? "").join("") || "?"; }
