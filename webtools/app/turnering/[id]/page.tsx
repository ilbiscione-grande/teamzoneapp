import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { dateSpan, feeLabel, formatLabels, placesLeft } from "../../../lib/tournament";
import { scoreLabel } from "../../../lib/tournament-schedule";
import { loadPublicTournament, publicMatchesByDay, swedishClock, swedishDayLabel } from "../../../lib/public-tournament";

// Results come in during the day: always read fresh.
export const dynamic = "force-dynamic";

type Props = { params: Promise<{ id: string }>; searchParams: Promise<{ klass?: string }> };

const valid = (id: string) => /^[0-9a-f-]{36}$/.test(id);

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { id } = await params;
  const tournament = valid(id) ? await loadPublicTournament(id) : null;
  return { title: tournament?.name ?? "Turnering" };
}

/** A tournament's public page: no account needed. */
export default async function PublicTournamentPage({ params, searchParams }: Props) {
  const { id } = await params;
  if (!valid(id)) notFound();
  const tournament = await loadPublicTournament(id);
  if (!tournament) notFound();
  const { klass } = await searchParams;
  const pitchName = new Map(tournament.pitches.map(pitch => [pitch.id, pitch.name]));
  const current = tournament.schedule.find(item => item.id === klass) ?? tournament.schedule[0];
  const groupName = new Map(current?.groups.map(group => [group.id, group.name]) ?? []);
  return (
    <div className="wt-wrap wt-section bk-page tp-public">
      <div>
        <p className="wt-kicker dark">Turnering</p>
        <h1 className="wt-page-title">{tournament.name}</h1>
        <p className="wt-small">
          {[dateSpan(tournament.starts_on, tournament.ends_on), tournament.location, tournament.sport,
            tournament.status === "finished" ? "Avslutad" : null].filter(Boolean).join(" · ")}
        </p>
      </div>

      {tournament.registration_is_open && (
        <p className="wt-note">
          Anmälan är öppen. <Link className="wt-link" href={`/turneringar/${tournament.id}`}>Anmäl ditt lag</Link> med ditt TeamZone-konto.
        </p>
      )}

      {current ? (
        <section className="tp-schedule">
          {tournament.schedule.length > 1 && (
            <nav className="tp-class-picker" aria-label="Klass">
              {tournament.schedule.map(item => (
                <Link key={item.id} href={`/turnering/${tournament.id}?klass=${item.id}`} aria-current={item.id === current.id ? "page" : undefined}>{item.name}</Link>
              ))}
            </nav>
          )}
          {current.groups.length > 0 && (
            <div className="tp-groups">
              {current.groups.map(group => (
                <div key={group.id} className="wt-panel tp-group">
                  <h2>{current.format === "pool" ? group.name : `Grupp ${group.name}`}</h2>
                  {group.standings ? (
                    <table className="tp-table">
                      <thead><tr><th>Lag</th><th title="Spelade">S</th><th title="Vunna">V</th><th title="Oavgjorda">O</th><th title="Förlorade">F</th><th title="Mål">+/−</th><th title="Poäng">P</th></tr></thead>
                      <tbody>
                        {group.standings.map((row, index) => (
                          <tr key={row.registration_id}>
                            <td><span className="tp-place">{index + 1}</span>{row.team_name}</td>
                            <td>{row.played}</td><td>{row.won}</td><td>{row.drawn}</td><td>{row.lost}</td>
                            <td>{row.goals_for}–{row.goals_against}</td><td><strong>{row.points}</strong></td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  ) : (
                    <ul className="tp-team-list">{group.team_ids.map(teamId => <li key={teamId}>{current.teams.find(t => t.registration_id === teamId)?.team_name ?? "Lag"}</li>)}</ul>
                  )}
                </div>
              ))}
            </div>
          )}
          <div className="wt-panel">
            <h2>Matcher {tournament.schedule.length > 1 ? `· ${current.name}` : ""}</h2>
            {current.matches.length === 0 ? <p>Inga matcher än.</p> : publicMatchesByDay(current.matches).map(day => (
              <div key={day.day ?? "none"} className="tp-day-block">
                <h3>{day.day ? swedishDayLabel(day.day) : "Utan tid"}</h3>
                <ul className="tp-matches">
                  {day.matches.map(match => (
                    <li key={match.id} className="tp-match" data-played={match.status === "played"}>
                      <div className="tp-match-when">
                        <strong>{match.starts_at ? swedishClock(match.starts_at) : "–"}</strong>
                        <span>{match.pitch_id ? pitchName.get(match.pitch_id) ?? "" : ""}</span>
                      </div>
                      <div className="tp-match-body">
                        <span className="tp-match-label">{match.label ?? (match.group_id ? `Grupp ${groupName.get(match.group_id) ?? ""}` : "")}</span>
                        <div className="tp-match-teams">
                          <span>{match.home_name ?? "?"}</span>
                          <strong className="tp-score">{scoreLabel(match) ?? "–"}</strong>
                          <span>{match.away_name ?? "?"}</span>
                        </div>
                      </div>
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </div>
        </section>
      ) : (
        <section className="wt-panel"><p>Spelschemat är inte publicerat än.</p></section>
      )}

      <section className="wt-panel">
        <h2>Klasser och lag</h2>
        {tournament.classes.length === 0 ? <p>Inga klasser än.</p> : (
          <ul className="bk-resource-list">
            {tournament.classes.map(item => {
              const left = placesLeft(item);
              return (
                <li key={item.id}>
                  <div>
                    <strong>{item.name}</strong>
                    <span>{[item.description, formatLabels[item.format], feeLabel(item.fee_sek),
                      left === null ? null : left === 0 ? "Full" : `${left} platser kvar`].filter(Boolean).join(" · ")}</span>
                    {item.teams.length > 0 && <span>{item.teams.map(team => team.team_name).join(", ")}</span>}
                  </div>
                </li>
              );
            })}
          </ul>
        )}
      </section>

      {(tournament.description || tournament.contact_email || tournament.organizer_name) && (
        <section className="wt-panel">
          <h2>Om turneringen</h2>
          {tournament.description && <p className="tp-text">{tournament.description}</p>}
          <p className="wt-small">{[tournament.organizer_name ? `Arrangör: ${tournament.organizer_name}` : null,
            tournament.contact_email ? `Kontakt: ${tournament.contact_email}` : null].filter(Boolean).join(" · ")}</p>
        </section>
      )}
    </div>
  );
}
