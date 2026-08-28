import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ContactForm } from "../../components/contact-form";
import { InactiveState } from "../../components/inactive-state";
import { SiteHeader } from "../../components/site-header";
import { canonicalUrl, getClubEvents, getClubPage, getPublications } from "../../lib/page-data";

export const dynamic = "force-dynamic";
type Props = { params: Promise<{ clubSlug: string }> };
type TeamLink = { id: string; slug: string; name: string; age_class?: string };
type Publication = { id: string; slug?: string; title: string; summary?: string; published_at: string };
type PublicEvent = { id: string; team_slug: string; team_name: string; title: string; starts_at: string; event_type: string; location_name?: string };
type Partner = { id: string; name: string; website_url?: string; logo_media_path?: string };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { clubSlug } = await params;
  try {
    const club = await getClubPage(clubSlug);
    if (club?.not_found) return {};
    if (club?.available === false) return { title: "Klubbsida", robots: { index: false, follow: false } };
    const description = club.description || `${club.name}s officiella webbplats på TeamZone.`;
    const canonical = await canonicalUrl(`/${club.slug}`);
    return { title: club.name, description, alternates: { canonical }, openGraph: { title: club.name, description, type: "website", url: canonical } };
  } catch { return { title: "Klubbsida", robots: { index: false, follow: false } }; }
}

export default async function ClubPage({ params }: Props) {
  try {
    const { clubSlug } = await params;
    const club = await getClubPage(clubSlug);
    if (club?.not_found) notFound();
    if (club?.available === false) return <InactiveState kind="klubb" />;
    const [publicationResult, eventResult] = await Promise.all([getPublications(club.id), getClubEvents(club.id)]);
    const news = (publicationResult?.items ?? []).filter((item: Publication & { content_type?: string }) => item.content_type === "news") as Publication[];
    const teams = (club.teams ?? []) as TeamLink[];
    const partners = (club.partners ?? []) as Partner[];
    const events = (eventResult?.items ?? []) as PublicEvent[];
    return (
      <main className="public-page">
        <SiteHeader />
        <section className="hero-card club-hero">
          {club.profile_media_path && <img className="club-badge" src={club.profile_media_path} alt={`${club.name}s klubbmärke`} />}
          <div><p className="eyebrow">Officiell klubbsida</p><h1>{club.name}</h1><div className="hero-meta">{club.locality && <span className="pill">{club.locality}</span>}<span className="verified-pill">Verifierad publicering</span></div></div>
        </section>
        <nav className="section-nav" aria-label="Klubbsidan"><a href="#om">Om klubben</a><a href="#nyheter">Nyheter</a><a href="#lag">Lag</a><a href="#handelser">Händelser</a><a href="#partners">Partners</a><a href="#kontakt">Kontakt</a></nav>
        <section id="om" className="panel feature-panel"><p className="eyebrow">Klubben</p><h2>Välkommen till {club.name}</h2><p>{club.description || "Klubben har inte publicerat någon presentation ännu."}</p></section>
        <div className="content-grid">
          <section id="nyheter" className="panel"><p className="eyebrow">Senaste nytt</p><h2>Nyheter</h2>{news.length ? <div className="card-list">{news.map((item) => <article className="story-card" key={item.id}><time>{formatDate(item.published_at)}</time><h3>{item.slug ? <Link href={`/${club.slug}/nyheter/${item.slug}`}>{item.title}</Link> : item.title}</h3>{item.summary && <p>{item.summary}</p>}</article>)}</div> : <Empty text="Klubben har inte publicerat några nyheter ännu." />}</section>
          <section id="lag" className="panel"><p className="eyebrow">I klubben</p><h2>Våra lag</h2>{teams.length ? <div className="team-links">{teams.map((team) => <Link key={team.id} href={`/${club.slug}/${team.slug}`}><strong>{team.name}</strong>{team.age_class && <span>{team.age_class}</span>}<span aria-hidden="true">→</span></Link>)}</div> : <Empty text="Inga lag är publicerade ännu." />}</section>
        </div>
        <div className="content-grid balanced">
          <section id="handelser" className="panel"><p className="eyebrow">På gång</p><h2>Händelser</h2>{events.length ? <div className="event-list">{events.map((event) => <article key={event.id}><time dateTime={event.starts_at}>{formatEventDate(event.starts_at)}</time><div><strong>{event.title}</strong><span><Link href={`/${club.slug}/${event.team_slug}`}>{event.team_name}</Link>{event.location_name ? ` · ${event.location_name}` : ""}</span></div></article>)}</div> : <Empty text="Publicerade händelser visas här när klubbens lag har lagt ut dem." />}</section>
          <section id="partners" className="panel"><p className="eyebrow">Tillsammans med</p><h2>Partners</h2>{partners.length ? <div className="partner-list">{partners.map((partner) => partner.website_url ? <a key={partner.id} href={partner.website_url} target="_blank" rel="noopener noreferrer">{partner.logo_media_path && <img src={partner.logo_media_path} alt="" />}<span>{partner.name}</span></a> : <span key={partner.id}>{partner.logo_media_path && <img src={partner.logo_media_path} alt="" />}{partner.name}</span>)}</div> : <Empty text="Klubben har inte publicerat några partners ännu." />}</section>
        </div>
        <section id="kontakt" className="panel contact-panel"><div><p className="eyebrow">Kontakt</p><h2>Kontakta {club.name}</h2><p>Dina uppgifter används endast för att hantera kontakten och raderas enligt TeamZones retentionregler.</p></div><ContactForm clubId={club.id} /></section>
      </main>
    );
  } catch (error) {
    if ((error as { digest?: string }).digest?.startsWith("NEXT_HTTP_ERROR_FALLBACK;404")) throw error;
    return <InactiveState kind="klubb" />;
  }
}

function Empty({ text }: { text: string }) { return <div className="empty-note">{text}</div>; }
function formatDate(value: string) { return new Intl.DateTimeFormat("sv-SE", { dateStyle: "medium" }).format(new Date(value)); }
function formatEventDate(value: string) { return new Intl.DateTimeFormat("sv-SE", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value)); }
