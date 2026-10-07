import type { Metadata } from "next";
import Link from "next/link";
import { WrittenMatchReport } from "../../../components/written-match-report";
import { notFound } from "next/navigation";
import { InactiveState } from "../../../components/inactive-state";
import { FollowButton } from "../../../components/follow-button";
import { AdminEntry } from "../../../components/admin/admin-entry";
import { ClubFooter, ClubHeader, Crest, Empty, EventCard, NewsGrid, ResultCard, SectionHead, clubSiteClass, ClubTheme, initials, type CalendarEvent, type NewsItem, type ResultItem } from "../../../components/club-site";
import { canonicalUrl, getClubPage, getPublications, getTeamEvents, getTeamResults, getTeamPage } from "../../../lib/page-data";

export const dynamic = "force-dynamic";
type Props = { params: Promise<{ clubSlug: string; teamSlug: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { clubSlug, teamSlug } = await params;
  try {
    const team = await getTeamPage(clubSlug, teamSlug);
    if (team?.not_found) return {};
    if (team?.available === false) return { title: "Lagsida", robots: { index: false, follow: false } };
    const canonical = await canonicalUrl(`/${team.club_slug}/${team.slug}`);
    return { title: team.name, description: `${team.name}s lagkanal på TeamZone.`, alternates: { canonical }, openGraph: { title: team.name, type: "website", url: canonical } };
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
    const [publicationResult, eventResult, resultData] = await Promise.all([getPublications(club.id, team.id), getTeamEvents(team.id), getTeamResults(team.id)]);
    const results = (resultData?.items ?? []) as ResultItem[];
    const news = (publicationResult?.items ?? []).filter((item: NewsItem & { content_type?: string }) => item.content_type === "news") as NewsItem[];
    const events = (eventResult?.items ?? []) as CalendarEvent[];
    const now = Date.now();
    const upcoming = events.filter((event) => new Date(event.starts_at).getTime() >= now).sort(byDate);
    const previous = events.filter((event) => new Date(event.starts_at).getTime() < now).sort((a, b) => -byDate(a, b));
    const [next, ...later] = upcoming;
    const latest = results[0];
    const clubHref = `/${clubSlug}`;
    const teams = (club.teams ?? []) as { id: string; slug: string; name: string }[];
    return (
      <main className={clubSiteClass(club)}><ClubTheme club={club} />
        <ClubHeader clubName={club.name} clubHref={clubHref} crest={club.profile_media_path}>
          <a href="#oversikt">Översikt</a>{results.length > 0 && <a href="#resultat">Resultat</a>}<a href="#handelser">Kalender</a><a href="#nyheter">Nyheter</a><Link href={`/${clubSlug}`}>Till {club.name}</Link>
        </ClubHeader>

        <section className="cs-hero team">
          <span className="cs-hero-mark" aria-hidden="true">{initials(team.name)}</span>
          <div className="cs-wrap cs-hero-inner">
            <Crest name={club.name} src={club.profile_media_path} size="lg" />
            <div className="cs-hero-text">
              <p className="cs-kicker">Lagkanal · <Link href={`/${clubSlug}`}>{club.name}</Link></p>
              <h1>{team.name}</h1>
              <div className="cs-hero-meta">{team.age_class && <span>{team.age_class}</span>}<span className={`cs-verified${club.official ? " official" : ""}`}>{club.official ? "officiellt verifierad klubb" : "inofficiell klubb"}</span></div>
              <div className="cs-hero-actions"><FollowButton channel={{ kind: "team", id: team.id, name: team.name, slug: team.slug, club_slug: club.slug }} /><AdminEntry clubSlug={club.slug} section="matcher" /></div>
            </div>
          </div>
        </section>

        {(next || latest) && (
          <section className="cs-matchbar" aria-label="Matchcenter">
            <div className="cs-wrap">
              <SectionHead title="Matchcenter" />
              <div className="cs-center">
                {next && <div><p className="cs-center-label">Nästa</p><EventCard event={next} hero /></div>}
                {latest && <div><p className="cs-center-label">Senaste resultat</p><ResultCard result={latest} teamName={team.name} /></div>}
              </div>
            </div>
          </section>
        )}

        <section id="oversikt" className="cs-section">
          <div className="cs-wrap cs-about">
            <div><p className="cs-kicker">Laget</p><h2 className="cs-title">{team.name}</h2><p className="cs-lead">{team.description || "Lagets publicerade information och innehåll samlas här."}</p></div>
            <dl className="cs-facts">
              <div><dt>Klubb</dt><dd><Link href={`/${clubSlug}`}>{club.name}</Link></dd></div>
              {team.age_class && <div><dt>Åldersklass</dt><dd>{team.age_class}</dd></div>}
              <div><dt>Kommande</dt><dd>{upcoming.length}</dd></div>
            </dl>
          </div>
        </section>

        {results.length > 0 && (
          <section id="resultat" className="cs-section alt">
            <div className="cs-wrap">
              <SectionHead kicker="Färdigspelat" title="Senaste slutresultaten" />
              <div className="cs-results">{results.map(result => <ResultCard key={result.id} result={result} teamName={team.name}><WrittenMatchReport text={result.report_text} /></ResultCard>)}</div>
            </div>
          </section>
        )}

        <section id="handelser" className="cs-section">
          <div className="cs-wrap">
            <SectionHead kicker="Kalender" title="Kommande händelser" />
            {upcoming.length ? <div className="cs-events">{(next ? [next, ...later] : later).map(event => <EventCard key={event.id} event={event} />)}</div> : <Empty text="Inga kommande händelser är publicerade." />}
            <h3 className="cs-subhead">Tidigare</h3>
            {previous.length ? <div className="cs-events past">{previous.map(event => <EventCard key={event.id} event={event} />)}</div> : <Empty text="Inga tidigare händelser är publicerade." />}
          </div>
        </section>

        <section id="nyheter" className="cs-section alt">
          <div className="cs-wrap">
            <SectionHead kicker="Från laget" title="Nyheter" />
            {news.length ? <NewsGrid items={news} clubSlug={clubSlug} clubName={club.name} crest={club.profile_media_path} /> : <Empty text="Laget har inte publicerat några nyheter ännu." />}
          </div>
        </section>

        <ClubFooter clubName={club.name} clubHref={clubHref} crest={club.profile_media_path} locality={club.locality} teams={teams} />
      </main>
    );
  } catch (error) {
    if ((error as { digest?: string }).digest?.startsWith("NEXT_HTTP_ERROR_FALLBACK;404")) throw error;
    return <InactiveState kind="lag" />;
  }
}

function byDate(a: CalendarEvent, b: CalendarEvent) { return new Date(a.starts_at).getTime() - new Date(b.starts_at).getTime(); }
