// Turneringsplaneraren's schedule: shapes from the schedule API, and the
// planning done in the browser (groups, round-robin, play-off brackets and
// times). The server saves a class's plan and keeps results and tables.

export type Pitch = { id: string; name: string; sort_order: number };

export type StandingRow = {
  registration_id: string;
  team_name: string;
  played: number;
  won: number;
  drawn: number;
  lost: number;
  goals_for: number;
  goals_against: number;
  points: number;
};

export type ScheduleGroup = {
  id: string;
  name: string;
  sort_order: number;
  team_ids: string[];
  complete: boolean;
  /** Group play only; pools have no table. */
  standings: StandingRow[] | null;
};

export type ScheduleMatch = {
  id: string;
  class_id: string;
  group_id: string | null;
  stage: "group" | "playoff";
  round: number;
  label: string | null;
  sort_order: number;
  home_registration_id: string | null;
  away_registration_id: string | null;
  /** The team, or where it comes from: "1:a grupp A", "Vinnare Semifinal 1". */
  home_name: string | null;
  away_name: string | null;
  pitch_id: string | null;
  starts_at: string | null;
  ends_at: string | null;
  status: "scheduled" | "played";
  home_score: number | null;
  away_score: number | null;
  home_penalties: number | null;
  away_penalties: number | null;
};

export type ScheduleClass = {
  id: string;
  name: string;
  format: "groups_playoff" | "pool";
  match_minutes: number | null;
  points_win: number;
  points_draw: number;
  schedule_published: boolean;
  teams: { registration_id: string; team_name: string; club_name: string | null }[];
  groups: ScheduleGroup[];
  matches: ScheduleMatch[];
};

export type Schedule = { pitches: Pitch[]; classes: ScheduleClass[] };

/** "A", "B"... "Z", then "AA". */
export function groupName(index: number): string {
  const letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
  return index < letters.length ? letters[index] : letters[Math.floor(index / letters.length) - 1] + letters[index % letters.length];
}

/** Teams into groups in a snake, so the first registered spread out. */
export function distributeTeams<T>(teams: T[], groupCount: number): T[][] {
  const count = Math.max(1, Math.min(groupCount, teams.length || 1));
  const groups: T[][] = Array.from({ length: count }, () => []);
  teams.forEach((team, index) => {
    const lap = Math.floor(index / count);
    const position = index % count;
    groups[lap % 2 === 0 ? position : count - 1 - position].push(team);
  });
  return groups;
}

/** Everyone meets everyone once, round by round (the circle method); home and away alternate. */
export function roundRobin<T>(teams: T[]): [T, T][][] {
  const list: (T | null)[] = [...teams];
  if (list.length < 2) return [];
  if (list.length % 2 === 1) list.push(null);
  const rounds: [T, T][][] = [];
  const n = list.length;
  for (let round = 0; round < n - 1; round++) {
    const pairs: [T, T][] = [];
    for (let i = 0; i < n / 2; i++) {
      const a = list[i], b = list[n - 1 - i];
      if (a === null || b === null) continue;
      pairs.push(round % 2 === 0 ? [a, b] : [b, a]);
    }
    rounds.push(pairs);
    // Keep the first, turn the others one step.
    list.splice(1, 0, list.pop()!);
  }
  return rounds;
}

export type PlannedGroupMatch = { group: number; round: number; home: string; away: string };

/** Every group's round-robin, round by round across the groups. */
export function groupMatches(groups: string[][]): PlannedGroupMatch[] {
  const all: PlannedGroupMatch[] = [];
  groups.forEach((teams, group) => roundRobin(teams).forEach((pairs, index) =>
    pairs.forEach(([home, away]) => all.push({ group, round: index + 1, home, away }))));
  return all.sort((a, b) => a.round - b.round || a.group - b.group);
}

export type Source =
  | { kind: "group_place"; group: number; place: number }
  | { kind: "winner" | "loser"; match: number };

export type PlannedPlayoffMatch = { round: number; label: string; home_source: Source; away_source: Source };

/** 1 v 4, 2 v 3; 1 v 8, 4 v 5, 2 v 7, 3 v 6: the best meet last. */
function bracketOrder(size: number): number[] {
  let order = [1];
  while (order.length < size) {
    const next = order.length * 2 + 1;
    order = order.flatMap(seed => [seed, next - seed]);
  }
  return order;
}

const roundNames: Record<number, string> = { 2: "Final", 4: "Semifinal", 8: "Kvartsfinal", 16: "Åttondelsfinal", 32: "Sextondelsfinal" };

/**
 * A knockout for the given places from every group: the group winners
 * first, then the seconds and so on, crossing groups in the first round.
 * The number of teams must be 2, 4, 8, 16 or 32. Indexes in sources start
 * at `offset`, the bracket's place among the class's play-off matches.
 */
export function playoffBracket(groupCount: number, places: number[], prefix: string, bronze: boolean, offset = 0): PlannedPlayoffMatch[] | null {
  const seeds: Source[] = [];
  // Seeded by place, then group: with two groups A1 meets B2 and B1 meets A2.
  for (const place of places) {
    for (let group = 0; group < groupCount; group++) seeds.push({ kind: "group_place", group, place });
  }
  const size = seeds.length;
  if (!roundNames[size]) return null;
  // "Semifinal 1", or with a prefix "A-semifinal 1".
  const named = (base: string) => prefix ? `${prefix}${base.toLowerCase()}` : base;
  const name = (teams: number, index: number, count: number) =>
    `${named(roundNames[teams])}${count > 1 ? ` ${index + 1}` : ""}`;
  const matches: PlannedPlayoffMatch[] = [];
  const order = bracketOrder(size);
  let current: number[] = [];
  let round = 1;
  for (let i = 0; i < size / 2; i++) {
    matches.push({ round, label: name(size, i, size / 2), home_source: seeds[order[i * 2] - 1], away_source: seeds[order[i * 2 + 1] - 1] });
    current.push(offset + matches.length - 1);
  }
  let teams = size / 2;
  while (teams >= 2) {
    round++;
    const next: number[] = [];
    if (teams === 2 && bronze) {
      matches.push({ round, label: named("Bronsmatch"), home_source: { kind: "loser", match: current[0] }, away_source: { kind: "loser", match: current[1] } });
    }
    for (let i = 0; i < teams / 2; i++) {
      matches.push({ round, label: name(teams, i, teams / 2), home_source: { kind: "winner", match: current[i * 2] }, away_source: { kind: "winner", match: current[i * 2 + 1] } });
      next.push(offset + matches.length - 1);
    }
    current = next;
    teams /= 2;
  }
  return matches;
}

export type Day = { date: string; start: string; end: string };
export type Busy = { pitch_id: string | null; starts_at: string; ends_at: string };
export type Timed = { pitch_id: string; starts_at: string; ends_at: string };

/** A local date and "HH:MM" as an instant. */
export function localTime(date: string, time: string): Date {
  const [y, m, d] = date.split("-").map(Number);
  const [h, min] = time.split(":").map(Number);
  return new Date(y, m - 1, d, h, min);
}

/**
 * Times for matches in order: the earliest free pitch and time, each team
 * resting at least one match between its games when it can, and no match
 * before what it depends on has ended. Null for a match that does not fit.
 */
export function assignTimes(
  items: { teams: string[]; dependsOn?: number[]; notBefore?: Date }[],
  options: { pitches: string[]; days: Day[]; minutes: number; gap: number; rest: boolean; busy: Busy[] },
): (Timed | null)[] {
  const step = (options.minutes + options.gap) * 60e3;
  const length = options.minutes * 60e3;
  const slots: number[] = [];
  for (const day of options.days) {
    const end = localTime(day.date, day.end).getTime();
    for (let t = localTime(day.date, day.start).getTime(); t + length <= end; t += step) slots.push(t);
  }
  const taken = options.busy.map(item => ({ pitch: item.pitch_id, from: new Date(item.starts_at).getTime(), to: new Date(item.ends_at).getTime() }));
  const placed: (Timed | null)[] = [];
  const teamTimes = new Map<string, number[]>();
  const fits = (item: (typeof items)[number], start: number, pitch: string, rest: boolean) => {
    const end = start + length;
    if (item.notBefore && start < item.notBefore.getTime()) return false;
    for (const index of item.dependsOn ?? []) {
      const before = placed[index];
      if (!before || start < new Date(before.ends_at).getTime() + options.gap * 60e3) return false;
    }
    if (taken.some(busy => busy.pitch === pitch && busy.from < end && start < busy.to)) return false;
    const spacing = rest ? step * 2 : step;
    return item.teams.every(team => (teamTimes.get(team) ?? []).every(other => Math.abs(other - start) >= spacing));
  };
  for (const item of items) {
    let found: Timed | null = null;
    for (const rest of options.rest ? [true, false] : [false]) {
      for (const start of slots) {
        const pitch = options.pitches.find(candidate => fits(item, start, candidate, rest));
        if (pitch) {
          found = { pitch_id: pitch, starts_at: new Date(start).toISOString(), ends_at: new Date(start + length).toISOString() };
          break;
        }
      }
      if (found) break;
    }
    placed.push(found);
    if (found) {
      const start = new Date(found.starts_at).getTime();
      taken.push({ pitch: found.pitch_id, from: start, to: start + length });
      for (const team of item.teams) teamTimes.set(team, [...(teamTimes.get(team) ?? []), start]);
    }
  }
  return placed;
}

/** The tournament's days, first to last. */
export function tournamentDays(startsOn: string, endsOn: string): string[] {
  const days: string[] = [];
  const pad = (n: number) => String(n).padStart(2, "0");
  for (let day = localTime(startsOn, "12:00"); ; day.setDate(day.getDate() + 1)) {
    const key = `${day.getFullYear()}-${pad(day.getMonth() + 1)}-${pad(day.getDate())}`;
    days.push(key);
    if (key >= endsOn || days.length > 31) break;
  }
  return days;
}

/** "2–1", "1–1 (4–3 str.)", or null before it is played. */
export function scoreLabel(match: ScheduleMatch): string | null {
  if (match.status !== "played" || match.home_score === null || match.away_score === null) return null;
  const penalties = match.home_penalties !== null && match.away_penalties !== null ? ` (${match.home_penalties}–${match.away_penalties} str.)` : "";
  return `${match.home_score}–${match.away_score}${penalties}`;
}

/** Matches by local day, in time order; unscheduled ones last. */
export function matchesByDay(matches: ScheduleMatch[]): { day: string | null; matches: ScheduleMatch[] }[] {
  const pad = (n: number) => String(n).padStart(2, "0");
  const key = (value: string | null) => {
    if (!value) return null;
    const date = new Date(value);
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
  };
  const sorted = [...matches].sort((a, b) =>
    (a.starts_at === null ? 1 : 0) - (b.starts_at === null ? 1 : 0)
    || (a.starts_at ?? "").localeCompare(b.starts_at ?? "")
    || a.stage.localeCompare(b.stage) || a.round - b.round || a.sort_order - b.sort_order);
  const days: { day: string | null; matches: ScheduleMatch[] }[] = [];
  for (const match of sorted) {
    const day = key(match.starts_at);
    const last = days[days.length - 1];
    if (last && last.day === day) last.matches.push(match);
    else days.push({ day, matches: [match] });
  }
  return days;
}
