"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { tournamentError, type Tournament } from "../../lib/tournament";
import {
  assignTimes, distributeTeams, groupMatches, groupName, localTime, matchesByDay, playoffBracket, scoreLabel, tournamentDays,
  type Busy, type Day, type PlannedPlayoffMatch, type Schedule, type ScheduleClass, type ScheduleMatch, type Source,
} from "../../lib/tournament-schedule";
import { useAccount } from "../account";

const dayLabel = (key: string) => localTime(key, "12:00").toLocaleDateString("sv-SE", { weekday: "long", day: "numeric", month: "long" });
const localDateKey = (iso: string) => new Date(iso).toLocaleDateString("sv-SE");
const clock = (iso: string) => new Date(iso).toLocaleTimeString("sv-SE", { hour: "2-digit", minute: "2-digit" });

/** Pitches, then a class's groups, schedule, tables and play-off. */
export function ScheduleTab({ tournament }: { tournament: Tournament }) {
  const { client } = useAccount();
  const [schedule, setSchedule] = useState<Schedule | null>(null);
  const [error, setError] = useState("");
  const [classId, setClassId] = useState("");

  const load = useCallback(async () => {
    if (!client) return;
    const { data, error: loadError } = await client.schema("api").rpc("get_tournament_schedule", { target_tournament_id: tournament.id });
    if (loadError) { setError(tournamentError(loadError)); return; }
    setSchedule(data as Schedule);
  }, [client, tournament.id]);
  useEffect(() => { void load(); }, [load]);

  if (error) return <p className="wt-error" role="alert">{error}</p>;
  if (!schedule) return <p className="wt-status">Laddar…</p>;
  const organizer = tournament.role === "organizer";
  const current = schedule.classes.find(item => item.id === classId) ?? schedule.classes[0];
  return (
    <div className="tp-schedule">
      {organizer && <PitchesAdmin tournament={tournament} schedule={schedule} onChanged={load} />}
      {schedule.classes.length === 0 ? (
        <section className="wt-panel"><p>{tournament.role ? "Lägg upp klasser först." : "Spelschemat är inte publicerat än."}</p></section>
      ) : (
        <>
          {schedule.classes.length > 1 && (
            <div className="tp-class-picker" role="tablist" aria-label="Klass">
              {schedule.classes.map(item => (
                <button key={item.id} type="button" role="tab" aria-selected={item.id === current.id} onClick={() => setClassId(item.id)}>{item.name}</button>
              ))}
            </div>
          )}
          <ClassSchedule key={current.id} tournament={tournament} schedule={schedule} item={current} onChanged={load} />
        </>
      )}
    </div>
  );
}

function PitchesAdmin({ tournament, schedule, onChanged }: { tournament: Tournament; schedule: Schedule; onChanged: () => void }) {
  const { client } = useAccount();
  const [name, setName] = useState("");
  const [error, setError] = useState("");
  if (!client) return null;
  const run = async (call: () => PromiseLike<{ error: { message?: string } | null }>) => {
    setError("");
    const { error: callError } = await call();
    if (callError) { setError(tournamentError(callError)); return false; }
    onChanged();
    return true;
  };
  return (
    <section className="wt-panel">
      <h2>Planer</h2>
      {error && <p className="wt-error" role="alert">{error}</p>}
      {schedule.pitches.length === 0 && <p>Lägg upp planerna som turneringen spelas på.</p>}
      <div className="tp-chips">
        {schedule.pitches.map(pitch => (
          <span key={pitch.id} className="tp-chip">{pitch.name}
            <button type="button" aria-label={`Ta bort ${pitch.name}`} onClick={() => void run(() => client.schema("api").rpc("delete_tournament_pitch", { target_pitch_id: pitch.id }))}>×</button>
          </span>
        ))}
      </div>
      <form className="tp-inline" onSubmit={async event => {
        event.preventDefault();
        if (await run(() => client.schema("api").rpc("save_tournament_pitch", { target_tournament_id: tournament.id, target_pitch_id: null, pitch_name: name, pitch_sort_order: schedule.pitches.length + 1 }))) setName("");
      }}>
        <input value={name} onChange={event => setName(event.target.value)} maxLength={60} placeholder="T.ex. Plan 1, Konstgräs A" aria-label="Planens namn" />
        <button type="submit" className="wt-button small" disabled={!name.trim()}>Lägg till</button>
      </form>
    </section>
  );
}

/** Days, pitches and match length for planning times. */
type Plan = { days: (Day & { on: boolean })[]; pitches: string[]; minutes: string; gap: string; rest: boolean };

function usePlan(tournament: Tournament, schedule: Schedule, item: ScheduleClass) {
  return useState<Plan>(() => ({
    days: tournamentDays(tournament.starts_on, tournament.ends_on).map(date => ({ date, start: "09:00", end: "17:00", on: true })),
    pitches: schedule.pitches.map(pitch => pitch.id),
    minutes: String(item.match_minutes ?? 15),
    gap: "5",
    rest: true,
  }));
}

function PlanFields({ plan, setPlan, schedule }: { plan: Plan; setPlan: (plan: Plan) => void; schedule: Schedule }) {
  return (
    <div className="tp-plan">
      <fieldset>
        <legend>Dagar och tider</legend>
        {plan.days.map((day, index) => (
          <div key={day.date} className="tp-day">
            <label className="wt-check"><input type="checkbox" checked={day.on} onChange={event => setPlan({ ...plan, days: plan.days.map((d, i) => i === index ? { ...d, on: event.target.checked } : d) })} /><span>{dayLabel(day.date)}</span></label>
            <input type="time" value={day.start} disabled={!day.on} aria-label="Första match" onChange={event => setPlan({ ...plan, days: plan.days.map((d, i) => i === index ? { ...d, start: event.target.value } : d) })} />
            <span>–</span>
            <input type="time" value={day.end} disabled={!day.on} aria-label="Sista match slut" onChange={event => setPlan({ ...plan, days: plan.days.map((d, i) => i === index ? { ...d, end: event.target.value } : d) })} />
          </div>
        ))}
      </fieldset>
      <fieldset>
        <legend>Planer</legend>
        {schedule.pitches.length === 0 ? <p className="wt-small">Lägg upp planer överst.</p> : schedule.pitches.map(pitch => (
          <label key={pitch.id} className="wt-check"><input type="checkbox" checked={plan.pitches.includes(pitch.id)} onChange={event => setPlan({ ...plan, pitches: event.target.checked ? [...plan.pitches, pitch.id] : plan.pitches.filter(id => id !== pitch.id) })} /><span>{pitch.name}</span></label>
        ))}
      </fieldset>
      <div className="bk-times">
        <label>Matchtid, minuter<input inputMode="numeric" value={plan.minutes} onChange={event => setPlan({ ...plan, minutes: event.target.value })} /></label>
        <label>Paus mellan matcher, minuter<input inputMode="numeric" value={plan.gap} onChange={event => setPlan({ ...plan, gap: event.target.value })} /></label>
      </div>
      <label className="wt-check"><input type="checkbox" checked={plan.rest} onChange={event => setPlan({ ...plan, rest: event.target.checked })} /><span>Lagen vilar minst en match mellan sina matcher när det går</span></label>
    </div>
  );
}

/** The plan's settings checked, or the sentence for what is wrong. */
function planOptions(plan: Plan, busy: Busy[]) {
  const minutes = Number(plan.minutes), gap = Number(plan.gap);
  if (!Number.isInteger(minutes) || minutes < 1 || minutes > 240) return "Matchtiden är hela minuter, 1–240.";
  if (!Number.isInteger(gap) || gap < 0 || gap > 120) return "Pausen är hela minuter, 0–120.";
  const days = plan.days.filter(day => day.on && day.start < day.end);
  if (days.length === 0) return "Välj minst en dag, med sluttid efter starttid.";
  if (plan.pitches.length === 0) return "Välj minst en plan.";
  return { pitches: plan.pitches, days, minutes, gap, rest: plan.rest, busy };
}

/** Other classes' timed matches, which take their pitches. */
function busyOutside(schedule: Schedule, classId: string, extra: ScheduleMatch[] = []): Busy[] {
  return [...schedule.classes.filter(item => item.id !== classId).flatMap(item => item.matches), ...extra]
    .filter(match => match.starts_at && match.ends_at)
    .map(match => ({ pitch_id: match.pitch_id, starts_at: match.starts_at!, ends_at: match.ends_at! }));
}

function ClassSchedule({ tournament, schedule, item, onChanged }: { tournament: Tournament; schedule: Schedule; item: ScheduleClass; onChanged: () => void }) {
  const { client } = useAccount();
  const [error, setError] = useState("");
  const organizer = tournament.role === "organizer";
  const staff = tournament.role !== null;
  const played = item.matches.some(match => match.status === "played");
  const groupStage = item.matches.filter(match => match.stage === "group");
  const playoff = item.matches.filter(match => match.stage === "playoff");
  const pitchName = useMemo(() => new Map(schedule.pitches.map(pitch => [pitch.id, pitch.name])), [schedule.pitches]);
  const groupOf = useMemo(() => new Map(item.groups.map(group => [group.id, group.name])), [item.groups]);
  return (
    <section className="tp-class">
      {error && <p className="wt-error" role="alert">{error}</p>}
      {organizer && (
        <div className="bk-admin-head">
          <p className="wt-small">{item.teams.length} godkända lag · {item.format === "pool" ? "poolspel utan tabell" : `${item.points_win} poäng för vinst, ${item.points_draw} för oavgjort`}</p>
          <label className="wt-check"><input type="checkbox" checked={item.schedule_published} onChange={async event => {
            setError("");
            const { error: publishError } = await client!.schema("api").rpc("set_tournament_class_schedule_published", { target_class_id: item.id, is_published: event.target.checked });
            if (publishError) setError(tournamentError(publishError)); else onChanged();
          }} /><span>Spelschemat är publicerat för lagen</span></label>
        </div>
      )}
      {organizer && !played && <GroupPlanner tournament={tournament} schedule={schedule} item={item} onChanged={onChanged} />}
      {item.groups.length > 0 && <Groups item={item} />}
      {organizer && item.format === "groups_playoff" && item.groups.length > 0 && !playoff.some(match => match.status === "played") && (
        <PlayoffPlanner tournament={tournament} schedule={schedule} item={item} onChanged={onChanged} />
      )}
      {item.matches.length === 0 ? (
        !organizer && <div className="wt-panel"><p>Inga matcher än.</p></div>
      ) : (
        <div className="wt-panel">
          <h2>Matcher</h2>
          {matchesByDay(item.matches).map(day => (
            <div key={day.day ?? "none"} className="tp-day-block">
              <h3>{day.day ? dayLabel(day.day) : "Utan tid"}</h3>
              <ul className="tp-matches">
                {day.matches.map(match => (
                  <MatchRow key={match.id} match={match} pitch={match.pitch_id ? pitchName.get(match.pitch_id) ?? null : null}
                    group={match.group_id ? groupOf.get(match.group_id) ?? null : null}
                    canReport={staff && item.format !== "pool"} canMove={organizer} schedule={schedule} onChanged={onChanged} />
                ))}
              </ul>
            </div>
          ))}
          <p className="wt-small">{groupStage.length} gruppmatcher{playoff.length ? ` · ${playoff.length} slutspelsmatcher` : ""}</p>
        </div>
      )}
    </section>
  );
}

function Groups({ item }: { item: ScheduleClass }) {
  const team = new Map(item.teams.map(t => [t.registration_id, t.team_name]));
  return (
    <div className="tp-groups">
      {item.groups.map(group => (
        <div key={group.id} className="wt-panel tp-group">
          <h2>{item.format === "pool" ? group.name : `Grupp ${group.name}`}</h2>
          {group.standings ? (
            <table className="tp-table">
              <thead><tr><th>Lag</th><th title="Spelade">S</th><th title="Vunna">V</th><th title="Oavgjorda">O</th><th title="Förlorade">F</th><th title="Målskillnad">+/−</th><th title="Poäng">P</th></tr></thead>
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
            <ul className="tp-team-list">{group.team_ids.map(id => <li key={id}>{team.get(id) ?? "Lag"}</li>)}</ul>
          )}
          {group.standings && group.complete && <p className="wt-small">Gruppen är färdigspelad.</p>}
        </div>
      ))}
    </div>
  );
}

function MatchRow({ match, pitch, group, canReport, canMove, schedule, onChanged }: {
  match: ScheduleMatch; pitch: string | null; group: string | null; canReport: boolean; canMove: boolean; schedule: Schedule; onChanged: () => void;
}) {
  const { client } = useAccount();
  const [editing, setEditing] = useState<"result" | "move" | null>(null);
  const [home, setHome] = useState(match.home_score?.toString() ?? "");
  const [away, setAway] = useState(match.away_score?.toString() ?? "");
  const [homePen, setHomePen] = useState(match.home_penalties?.toString() ?? "");
  const [awayPen, setAwayPen] = useState(match.away_penalties?.toString() ?? "");
  const [moveDay, setMoveDay] = useState(match.starts_at ? localDateKey(match.starts_at) : "");
  const [moveTime, setMoveTime] = useState(match.starts_at ? clock(match.starts_at) : "");
  const [movePitch, setMovePitch] = useState(match.pitch_id ?? "");
  const [error, setError] = useState("");
  const known = match.home_registration_id && match.away_registration_id;
  const level = match.stage === "playoff" && home !== "" && home === away;
  const save = async (clear = false) => {
    if (!client) return;
    setError("");
    const number = (value: string) => value.trim() === "" ? null : Number(value);
    const { error: saveError } = await client.schema("api").rpc("report_tournament_match_result", {
      target_match_id: match.id, result_home: clear ? null : number(home), result_away: clear ? null : number(away),
      result_home_penalties: clear || !level ? null : number(homePen), result_away_penalties: clear || !level ? null : number(awayPen),
    });
    if (saveError) { setError(tournamentError(saveError)); return; }
    setEditing(null);
    onChanged();
  };
  const move = async () => {
    if (!client) return;
    setError("");
    const minutes = match.starts_at && match.ends_at ? (new Date(match.ends_at).getTime() - new Date(match.starts_at).getTime()) : 15 * 60e3;
    const start = moveDay && moveTime ? localTime(moveDay, moveTime) : null;
    const { error: moveError } = await client.schema("api").rpc("set_tournament_match_time", {
      target_match_id: match.id, target_pitch_id: movePitch || null,
      match_starts_at: start?.toISOString() ?? null, match_ends_at: start ? new Date(start.getTime() + minutes).toISOString() : null,
    });
    if (moveError) { setError(tournamentError(moveError)); return; }
    setEditing(null);
    onChanged();
  };
  const score = scoreLabel(match);
  return (
    <li className="tp-match" data-played={match.status === "played"}>
      <div className="tp-match-when">
        <strong>{match.starts_at ? clock(match.starts_at) : "–"}</strong>
        <span>{pitch ?? ""}</span>
      </div>
      <div className="tp-match-body">
        <span className="tp-match-label">{match.label ?? (group ? `Grupp ${group}` : "")}</span>
        <div className="tp-match-teams">
          <span>{match.home_name ?? "?"}</span>
          <strong className="tp-score">{score ?? "–"}</strong>
          <span>{match.away_name ?? "?"}</span>
        </div>
        {editing === "result" && (
          <form className="tp-result" onSubmit={event => { event.preventDefault(); void save(); }}>
            <input inputMode="numeric" value={home} onChange={event => setHome(event.target.value)} aria-label={`Mål ${match.home_name}`} autoFocus />
            <span>–</span>
            <input inputMode="numeric" value={away} onChange={event => setAway(event.target.value)} aria-label={`Mål ${match.away_name}`} />
            {level && (
              <>
                <span className="wt-small">Straffar</span>
                <input inputMode="numeric" value={homePen} onChange={event => setHomePen(event.target.value)} aria-label={`Straffar ${match.home_name}`} />
                <span>–</span>
                <input inputMode="numeric" value={awayPen} onChange={event => setAwayPen(event.target.value)} aria-label={`Straffar ${match.away_name}`} />
              </>
            )}
            <button type="submit" className="wt-button small">Spara</button>
            {match.status === "played" && <button type="button" className="wt-button secondary small" onClick={() => void save(true)}>Rensa</button>}
            <button type="button" className="wt-button secondary small" onClick={() => setEditing(null)}>Avbryt</button>
          </form>
        )}
        {editing === "move" && (
          <form className="tp-result" onSubmit={event => { event.preventDefault(); void move(); }}>
            <input type="date" value={moveDay} onChange={event => setMoveDay(event.target.value)} aria-label="Dag" />
            <input type="time" value={moveTime} onChange={event => setMoveTime(event.target.value)} aria-label="Tid" />
            <select value={movePitch} onChange={event => setMovePitch(event.target.value)} aria-label="Plan">
              <option value="">Ingen plan</option>
              {schedule.pitches.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
            <button type="submit" className="wt-button small">Spara</button>
            <button type="button" className="wt-button secondary small" onClick={() => setEditing(null)}>Avbryt</button>
          </form>
        )}
        {error && <span className="wt-error" role="alert">{error}</span>}
      </div>
      {!editing && (canReport || canMove) && (
        <div className="bk-booking-actions">
          {canReport && known && <button type="button" className="wt-button secondary small" onClick={() => setEditing("result")}>{match.status === "played" ? "Ändra" : "Resultat"}</button>}
          {canMove && <button type="button" className="wt-button secondary small" onClick={() => setEditing("move")}>Flytta</button>}
        </div>
      )}
    </li>
  );
}

/** Groups and the group matches with times; saved at once, replacing the old. */
function GroupPlanner({ tournament, schedule, item, onChanged }: { tournament: Tournament; schedule: Schedule; item: ScheduleClass; onChanged: () => void }) {
  const { client } = useAccount();
  const [open, setOpen] = useState(item.groups.length === 0);
  const [groupCount, setGroupCount] = useState(String(item.groups.length || Math.max(1, Math.round(item.teams.length / 4))));
  // Each team's group: from the saved groups, or a fresh snake.
  const fresh = useCallback((count: number) => {
    const map = new Map<string, number>();
    distributeTeams(item.teams.map(t => t.registration_id), count).forEach((ids, group) => ids.forEach(id => map.set(id, group)));
    return map;
  }, [item.teams]);
  const [assignment, setAssignment] = useState<Map<string, number>>(() => {
    if (item.groups.length === 0) return fresh(Number(groupCount) || 1);
    const map = new Map<string, number>();
    item.groups.forEach((group, index) => group.team_ids.forEach(id => map.set(id, index)));
    item.teams.forEach(t => { if (!map.has(t.registration_id)) map.set(t.registration_id, 0); });
    return map;
  });
  const [plan, setPlan] = usePlan(tournament, schedule, item);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const count = Math.max(1, Math.min(Number(groupCount) || 1, item.teams.length || 1));

  if (!open) {
    return (
      <div className="bk-admin-head">
        <p className="wt-small">{item.matches.length ? "Grupper och tider kan göras om tills första resultatet är inlagt." : ""}</p>
        <button type="button" className="wt-button secondary" onClick={() => setOpen(true)}>Planera grupper och tider</button>
      </div>
    );
  }
  const create = async () => {
    if (!client) return;
    setError("");
    const options = planOptions(plan, busyOutside(schedule, item.id));
    if (typeof options === "string") { setError(options); return; }
    const groups = Array.from({ length: count }, (_, index) => item.teams.filter(t => assignment.get(t.registration_id) === index).map(t => t.registration_id));
    if (groups.some(group => group.length < 2)) { setError("Varje grupp behöver minst två lag."); return; }
    const planned = groupMatches(groups);
    const times = assignTimes(planned.map(match => ({ teams: [match.home, match.away] })), options);
    const missing = times.filter(time => time === null).length;
    if (missing) { setError(`${missing} av ${planned.length} matcher får inte plats. Lägg till en dag, en plan, längre speldagar eller kortare matcher.`); return; }
    if (item.matches.length && !window.confirm("Gruppspelet och slutspelet görs om från början. Fortsätta?")) return;
    setBusy(true);
    const { error: saveError } = await client.schema("api").rpc("save_tournament_class_schedule", {
      target_class_id: item.id, schedule_stage: "group",
      schedule_groups: groups.map((ids, index) => ({ name: item.format === "pool" ? `Pool ${index + 1}` : groupName(index), registration_ids: ids })),
      schedule_matches: planned.map((match, index) => ({ ...match, round: match.round, ...times[index] })),
    });
    setBusy(false);
    if (saveError) { setError(tournamentError(saveError)); return; }
    setOpen(false);
    onChanged();
  };
  return (
    <div className="wt-panel wt-form">
      <h2>Grupper och tider</h2>
      {item.teams.length < 2 ? <p>Klassen behöver minst två godkända lag.</p> : (
        <>
          <label>Antal {item.format === "pool" ? "pooler" : "grupper"}
            <input inputMode="numeric" value={groupCount} onChange={event => setGroupCount(event.target.value)} />
          </label>
          <div className="wt-actions">
            <button type="button" className="wt-button secondary small" onClick={() => setAssignment(fresh(count))}>Fördela lagen</button>
            <button type="button" className="wt-button secondary small" onClick={() => {
              const ids = item.teams.map(t => t.registration_id).sort(() => Math.random() - .5);
              const map = new Map<string, number>();
              distributeTeams(ids, count).forEach((group, index) => group.forEach(id => map.set(id, index)));
              setAssignment(map);
            }}>Lotta</button>
          </div>
          <div className="tp-groups">
            {Array.from({ length: count }, (_, index) => (
              <div key={index} className="tp-group-plan">
                <strong>{item.format === "pool" ? `Pool ${index + 1}` : `Grupp ${groupName(index)}`}</strong>
                {item.teams.filter(t => (assignment.get(t.registration_id) ?? 0) === index).map(t => (
                  <label key={t.registration_id}>
                    <span>{t.team_name}</span>
                    <select value={index} aria-label={`Grupp för ${t.team_name}`} onChange={event => setAssignment(new Map(assignment).set(t.registration_id, Number(event.target.value)))}>
                      {Array.from({ length: count }, (_, g) => <option key={g} value={g}>{item.format === "pool" ? `Pool ${g + 1}` : groupName(g)}</option>)}
                    </select>
                  </label>
                ))}
              </div>
            ))}
          </div>
          {item.teams.some(t => (assignment.get(t.registration_id) ?? 0) >= count) && <p className="wt-small">Några lag ligger i en grupp som inte finns längre. Tryck Fördela lagen.</p>}
          <PlanFields plan={plan} setPlan={setPlan} schedule={schedule} />
          {error && <p className="wt-error" role="alert">{error}</p>}
          <div className="wt-actions">
            <button type="button" className="wt-button" disabled={busy} onClick={() => void create()}>{item.matches.length ? "Gör om gruppspelet" : "Skapa gruppspel"}</button>
            {item.groups.length > 0 && <button type="button" className="wt-button secondary" onClick={() => setOpen(false)}>Avbryt</button>}
          </div>
        </>
      )}
    </div>
  );
}

/** A- and B-play-off from the group places, timed after the group play. */
function PlayoffPlanner({ tournament, schedule, item, onChanged }: { tournament: Tournament; schedule: Schedule; item: ScheduleClass; onChanged: () => void }) {
  const { client } = useAccount();
  const existing = item.matches.some(match => match.stage === "playoff");
  const [open, setOpen] = useState(false);
  const groupCount = item.groups.length;
  const smallest = Math.min(...item.groups.map(group => group.team_ids.length));
  const [aPlaces, setAPlaces] = useState(groupCount === 1 ? "4" : "2");
  const [bPlaces, setBPlaces] = useState("0");
  const [bronze, setBronze] = useState(false);
  const [plan, setPlan] = usePlan(tournament, schedule, item);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  if (!open) {
    return (
      <div className="bk-admin-head">
        <p className="wt-small">{existing ? "Slutspelet kan göras om tills första slutspelsmatchen är spelad." : "Gruppspelet är klart att följas av ett slutspel."}</p>
        <button type="button" className="wt-button secondary" onClick={() => setOpen(true)}>{existing ? "Gör om slutspelet" : "Planera slutspel"}</button>
      </div>
    );
  }
  const a = Number(aPlaces), b = Number(bPlaces);
  const create = async () => {
    if (!client) return;
    setError("");
    if (!Number.isInteger(a) || !Number.isInteger(b) || a < 1 || b < 0 || a + b > smallest) {
      setError(`Varje grupp har ${smallest} lag: A och B kan tillsammans ta högst så många per grupp.`); return;
    }
    const range = (from: number, n: number) => Array.from({ length: n }, (_, i) => from + i);
    const aBracket = playoffBracket(groupCount, range(1, a), b > 0 ? "A-" : "", bronze);
    const bBracket = b > 0 ? playoffBracket(groupCount, range(a + 1, b), "B-", false, aBracket?.length ?? 0) : [];
    if (!aBracket || !bBracket) { setError("Ett slutspel behöver 2, 4, 8, 16 eller 32 lag. Ändra hur många som går vidare."); return; }
    const matches: PlannedPlayoffMatch[] = [...aBracket, ...bBracket];
    const groupMatchesHere = item.matches.filter(match => match.stage === "group");
    const options = planOptions(plan, busyOutside(schedule, item.id, groupMatchesHere));
    if (typeof options === "string") { setError(options); return; }
    const lastGroup = Math.max(0, ...groupMatchesHere.filter(match => match.ends_at).map(match => new Date(match.ends_at!).getTime()));
    const after = new Date(lastGroup + options.gap * 60e3);
    const depends = (source: Source) => source.kind === "group_place" ? [] : [source.match];
    const times = assignTimes(matches.map(match => ({
      teams: [], notBefore: after, dependsOn: [...depends(match.home_source), ...depends(match.away_source)],
    })), { ...options, rest: false });
    const missing = times.filter(time => time === null).length;
    if (missing) { setError(`${missing} slutspelsmatcher får inte plats efter gruppspelet. Lägg till tid eller planer.`); return; }
    if (existing && !window.confirm("Slutspelet görs om. Fortsätta?")) return;
    setBusy(true);
    const { error: saveError } = await client.schema("api").rpc("save_tournament_class_schedule", {
      target_class_id: item.id, schedule_stage: "playoff", schedule_groups: null,
      schedule_matches: matches.map((match, index) => ({ ...match, ...times[index] })),
    });
    setBusy(false);
    if (saveError) { setError(tournamentError(saveError)); return; }
    setOpen(false);
    onChanged();
  };
  return (
    <div className="wt-panel wt-form">
      <h2>Slutspel</h2>
      <div className="bk-times">
        <label>Lag per grupp till {b > 0 ? "A-slutspel" : "slutspel"}<input inputMode="numeric" value={aPlaces} onChange={event => setAPlaces(event.target.value)} /></label>
        <label>Lag per grupp till B-slutspel<input inputMode="numeric" value={bPlaces} onChange={event => setBPlaces(event.target.value)} /></label>
      </div>
      <p className="wt-small">{groupCount} {groupCount === 1 ? "grupp" : "grupper"}: {Number.isInteger(a) ? a * groupCount : "?"} lag i {b > 0 ? "A" : "slutspelet"}{b > 0 ? `, ${b * groupCount} i B` : ""}. Gruppettor möter tvåor från andra grupper.</p>
      <label className="wt-check"><input type="checkbox" checked={bronze} onChange={event => setBronze(event.target.checked)} /><span>Bronsmatch</span></label>
      <PlanFields plan={plan} setPlan={setPlan} schedule={schedule} />
      {error && <p className="wt-error" role="alert">{error}</p>}
      <div className="wt-actions">
        <button type="button" className="wt-button" disabled={busy} onClick={() => void create()}>{existing ? "Gör om slutspelet" : "Skapa slutspel"}</button>
        <button type="button" className="wt-button secondary" onClick={() => setOpen(false)}>Avbryt</button>
      </div>
    </div>
  );
}
