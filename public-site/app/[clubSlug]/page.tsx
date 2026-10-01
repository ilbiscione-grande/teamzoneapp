import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ContactForm } from "../../components/contact-form";
import { InactiveState } from "../../components/inactive-state";
import { FollowButton } from "../../components/follow-button";
import { ClubFooter, ClubHeader, Crest, Empty, EventCard, NewsGrid, SectionHead, clubSiteClass, ClubTheme, initials, type CalendarEvent, type NewsItem } from "../../components/club-site";
import { canonicalUrl, getClubEvents, getClubPage, getPublications } from "../../lib/page-data";

export const dynamic = "force-dynamic";
type Props = { params: Promise<{ clubSlug: string }> };
type TeamLink = { id: string; slug: string; name: string; age_class?: string };
type Partner = { id: string; name: string; website_url?: string; logo_media_path?: string };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { clubSlug } = await params;
  try {
    const club = await getClubPage(clubSlug);
    if (club?.not_found) return {};
    if (club?.available === false) return { title: "Klubbsida", robots: { index: false, follow: false } };
    const description = club.description || `${club.name}s klubbsida på TeamZone.`;
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
    const news = (publicationResult?.items ?? []).filter((item: NewsItem & { content_type?: string }) => item.content_type === "news") as NewsItem[];
    const teams = (club.teams ?? []) as TeamLink[];
    const partners = (club.partners ?? []) as Partner[];
    const events = (eventResult?.items ?? []) as CalendarEvent[];
    const now = Date.now();
    const upcoming = events.filter(event => new Date(event.starts_at).getTime() >= now);
    const clubHref = `/${club.slug}`;
    const heroImage = news.find(item => item.media_path)?.media_path;
    return (
      <main className={clubSiteClass(club)}><ClubTheme club={club} />
        <ClubHeader clubName={club.name} clubHref={clubHref} crest={club.profile_media_path}>
          <a href="#nyheter">Nyheter</a><a href="#lag">Lag</a><a href="#handelser">Kalender</a><a href="#om">Om klubben</a><a href="#partners">Partners</a><a href="#kontakt">Kontakt</a>
        </ClubHeader>

        <section className="cs-hero">
          {heroImage ? <img className="cs-hero-image" src={heroImage} alt="" /> : <span className="cs-hero-mark" aria-hidden="true">{initials(club.name)}</span>}
          <div className="cs-wrap cs-hero-inner">
            <Crest name={club.name} src={club.profile_media_path} size="lg" />
            <div className="cs-hero-text">
              <p className="cs-kicker">Klubbsida{club.locality ? ` · ${club.locality}` : ""}</p>
              <h1>{club.name}</h1>
              <div className="cs-hero-meta"><span className={`cs-verified${club.official ? " official" : ""}`}>{club.official ? "Officiellt verifierad klubb" : "Inofficiell klubb"}</span>{teams.length > 0 && <span>{teams.length} lag</span>}</div>
              <div className="cs-hero-actions"><FollowButton channel={{ kind: "club", id: club.id, name: club.name, slug: club.slug }} /><a className="cs-button ghost" href="#kontakt">Kontakta klubben</a></div>
            </div>
          </div>
        </section>

        {upcoming.length > 0 && (
          <section className="cs-matchbar" aria-label="Kommande">
            <div className="cs-wrap">
              <SectionHead title="Kommande" href="#handelser" linkText="Hela kalendern" />
              <div className="cs-rail">{upcoming.slice(0, 3).map(event => <EventCard key={event.id} event={event} teamHref={event.team_slug ? `${clubHref}/${event.team_slug}` : undefined} />)}</div>
            </div>
          </section>
        )}

        <section id="nyheter" className="cs-section">
          <div className="cs-wrap">
            <SectionHead kicker="Senaste nytt" title="Nyheter" />
            {news.length ? <NewsGrid items={news} clubSlug={club.slug} clubName={club.name} crest={club.profile_media_path} /> : <Empty text="Klubben har inte publicerat några nyheter ännu." />}
          </div>
        </section>

        <section id="lag" className="cs-section alt">
          <div className="cs-wrap">
            <SectionHead kicker="I klubben" title="Våra lag" />
            {teams.length ? <div className="cs-teams">{teams.map(team => <Link key={team.id} className="cs-team-card" href={`${clubHref}/${team.slug}`}><Crest name={club.name} src={club.profile_media_path} size="sm" /><span><strong>{team.name}</strong>{team.age_class && <small>{team.age_class}</small>}</span><span className="cs-arrow" aria-hidden="true">→</span></Link>)}</div> : <Empty text="Inga lag är publicerade ännu." />}
          </div>
        </section>

        <section id="handelser" className="cs-section">
          <div className="cs-wrap">
            <SectionHead kicker="På gång" title="Kalender" />
            {events.length ? <div className="cs-events">{events.map(event => <EventCard key={event.id} event={event} teamHref={event.team_slug ? `${clubHref}/${event.team_slug}` : undefined} />)}</div> : <Empty text="Publicerade händelser visas här när klubbens lag har lagt ut dem." />}
          </div>
        </section>

        <section id="om" className="cs-section alt">
          <div className="cs-wrap cs-about">
            <div><p className="cs-kicker">Klubben</p><h2 className="cs-title">Välkommen till {club.name}</h2><p className="cs-lead">{club.description || "Klubben har inte publicerat någon presentation ännu."}</p></div>
            <dl className="cs-facts">
              {club.locality && <div><dt>Ort</dt><dd>{club.locality}</dd></div>}
              <div><dt>Lag</dt><dd>{teams.length}</dd></div>
              <div><dt>Status</dt><dd>{club.official ? "Verifierad" : "Ej verifierad"}</dd></div>
            </dl>
          </div>
        </section>

        <section id="partners" className="cs-section">
          <div className="cs-wrap">
            <SectionHead kicker="Tillsammans med" title="Partners" />
            {partners.length ? <div className="cs-partners">{partners.map(partner => partner.website_url
              ? <a key={partner.id} href={partner.website_url} target="_blank" rel="noopener noreferrer">{partner.logo_media_path ? <img src={partner.logo_media_path} alt={partner.name} /> : <span>{partner.name}</span>}</a>
              : <div key={partner.id}>{partner.logo_media_path ? <img src={partner.logo_media_path} alt={partner.name} /> : <span>{partner.name}</span>}</div>)}</div> : <Empty text="Klubben har inte publicerat några partners ännu." />}
          </div>
        </section>

        <section id="kontakt" className="cs-contact">
          <div className="cs-wrap cs-contact-grid">
            <div><p className="cs-kicker">Kontakt</p><h2 className="cs-title">Kontakta {club.name}</h2><p>Har du frågor om klubben, träningar eller medlemskap? Skicka ett meddelande så återkommer klubben.</p><p className="cs-fineprint">Dina uppgifter används endast för att hantera kontakten och raderas enligt TeamZones retentionregler.</p></div>
            <div className="cs-form-card"><ContactForm clubId={club.id} /></div>
          </div>
        </section>

        <ClubFooter clubName={club.name} clubHref={clubHref} crest={club.profile_media_path} locality={club.locality} teams={teams} />
      </main>
    );
  } catch (error) {
    if ((error as { digest?: string }).digest?.startsWith("NEXT_HTTP_ERROR_FALLBACK;404")) throw error;
    return <InactiveState kind="klubb" />;
  }
}
