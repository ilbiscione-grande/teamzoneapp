import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { InactiveState } from "../../../components/inactive-state";
import { SiteHeader } from "../../../components/site-header";
import { canonicalUrl, getClubPage, getPublications, getTeamEvents, getTeamPage } from "../../../lib/page-data";

export const dynamic = "force-dynamic";
type Props = { params: Promise<{ clubSlug: string; teamSlug: string }> };
type Publication = { id: string; slug?: string; title: string; summary?: string; published_at: string };
type PublicEvent = { id: string; title: string; starts_at: string; event_type: string; location_name?: string };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { clubSlug, teamSlug } = await params;
  try {
    const team = await getTeamPage(clubSlug, teamSlug);
    if (team?.not_found) return {};
    if (team?.available === false) return { title: "Lagsida", robots: { index: false, follow: false } };
    const canonical = await canonicalUrl(`/${team.club_slug}/${team.slug}`);
    return { title: team.name, description: `${team.name}s officiella lagkanal på TeamZone.`, alternates: { canonical }, openGraph: { title: team.name, type: "website", url: canonical } };
  } catch { return { title: "Lagsida", robots: { index: false, follow: false } }; }
}

export default async function TeamPage({ params }: Props) {
  try {
    const { clubSlug, teamSlug } = await params;
    const team = await getTeamPage(clubSlug, teamSlug);
    if (team?.not_found) notFound();
    if (team?.available === false) return <InactiveState kind="lag" />;
    const club = await getClubPage(clubSlug);
    if (club?.not_found) notFound();
    if (club?.available === false) return <InactiveState kind="lag" />;
    const [publicationResult, eventResult] = await Promise.all([getPublications(club.id, team.id), getTeamEvents(team.id)]);
    const news = (publicationResult?.items ?? []).filter((item: Publication & { content_type?: string }) => item.content_type === "news") as Publication[];
    const events = (eventResult?.items ?? []) as PublicEvent[];
    const now = Date.now();
    const upcoming = events.filter((event) => new Date(event.starts_at).getTime() >= now).sort(byDate);
    const previous = events.filter((event) => new Date(event.starts_at).getTime() < now).sort((a, b) => -byDate(a, b));
    return (
      <main className="public-page">
        <SiteHeader clubName={club.name} clubHref={`/${clubSlug}`} />
        <section className="hero-card team-hero"><p className="eyebrow">Officiell lagkanal</p><h1>{team.name}</h1><div className="hero-meta">{team.age_class && <span className="pill">{team.age_class}</span>}</div></section>
        <nav className="section-nav" aria-label="Lagsidan"><a href="#oversikt">Översikt</a><a href="#nyheter">Nyheter</a><a href="#handelser">Händelser</a></nav>
        <section id="oversikt" className="panel feature-panel"><p className="eyebrow">Laget</p><h2>{team.name}</h2><p>{team.description || "Lagets officiella information och publicerade innehåll samlas här."}</p></section>
        <div className="content-grid">
          <section id="handelser" className="panel"><p className="eyebrow">Kalender</p><h2>Kommande händelser</h2>{upcoming.length ? <EventList events={upcoming} /> : <Empty text="Inga kommande händelser är publicerade." />}<h3 className="subheading">Tidigare</h3>{previous.length ? <EventList events={previous} /> : <Empty text="Inga tidigare händelser är publicerade." />}</section>
          <section id="nyheter" className="panel"><p className="eyebrow">Från laget</p><h2>Nyheter</h2>{news.length ? <div className="card-list">{news.map((item) => <article className="story-card" key={item.id}><time>{formatDate(item.published_at)}</time><h3>{item.slug ? <Link href={`/${clubSlug}/nyheter/${item.slug}`}>{item.title}</Link> : item.title}</h3>{item.summary && <p>{item.summary}</p>}</article>)}</div> : <Empty text="Laget har inte publicerat några nyheter ännu." />}</section>
        </div>
        <Link className="back-link" href={`/${clubSlug}`}>Till {club.name}</Link>
      </main>
    );
  } catch (error) {
    if ((error as { digest?: string }).digest?.startsWith("NEXT_HTTP_ERROR_FALLBACK;404")) throw error;
    return <InactiveState kind="lag" />;
  }
}

function EventList({ events }: { events: PublicEvent[] }) { return <div className="event-list">{events.map((event) => <article key={event.id}><time dateTime={event.starts_at}>{formatDate(event.starts_at)}</time><div><strong>{event.title}</strong><span>{eventLabel(event.event_type)}{event.location_name ? ` · ${event.location_name}` : ""}</span></div></article>)}</div>; }
function Empty({ text }: { text: string }) { return <div className="empty-note">{text}</div>; }
function formatDate(value: string) { return new Intl.DateTimeFormat("sv-SE", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value)); }
function byDate(a: PublicEvent, b: PublicEvent) { return new Date(a.starts_at).getTime() - new Date(b.starts_at).getTime(); }
function eventLabel(type: string) { return ({ match: "Match", training: "Träning", meeting: "Möte", activity: "Aktivitet" } as Record<string, string>)[type] ?? "Händelse"; }
