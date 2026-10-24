// The match live on the team's public page (decision package 12): the
// match's course told as the app's report tells it, from the same wordings
// (PLM-07), and the clock as the app counts it. The feed holds only what
// may be public: kinds, minutes, sides, outcomes, and names that have a
// name consent (PLM-01); a missing name is the team's.
import wordings from "./match-report-wordings.json" with { type: "json" };

export type LiveFeedItem = {
  n: number;
  minute: number;
  type: "goal" | "shot" | "save" | "penalty" | "card" | "substitution" | "injury" | string;
  side: "us" | "opponent" | string;
  result?: string | null;
  player?: string | null;
  second?: string | null;
};

export type LiveClock = {
  started_at?: string | null;
  paused_at?: string | null;
  paused_seconds?: number | null;
  completed_at?: string | null;
  period_minutes?: number[] | null;
  current_period?: number | null;
  period_end?: { scheduled_minute?: number; elapsed_seconds?: number } | null;
  period_ended?: boolean | null;
};

export type LiveMatch = {
  id: string;
  title: string;
  starts_at: string;
  state: "live" | "completed" | string;
  score_us: number;
  score_opponent: number;
  clock: LiveClock;
  feed: LiveFeedItem[];
  opponent_name?: string | null;
  home_away?: string | null;
  updated_at: string;
};

type Wordings = typeof wordings;
type Grouped = Record<string, string[]>;

/** "12:e", "21:a": the minute as Swedish says it. */
export function ordinal(minute: number): string {
  const last = minute % 10, lastTwo = minute % 100;
  return `${minute}:${(last === 1 || last === 2) && lastTwo !== 11 && lastTwo !== 12 ? "a" : "e"}`;
}

/** "Lindström" → "Lindströms", "Aneby SK" → "Aneby SK:s", "Lukas" stays. */
function owner(name: string): string {
  if (!name) return name;
  const last = name[name.length - 1];
  if ("sxzSXZ".includes(last)) return name;
  if (/[A-ZÅÄÖ0-9]/.test(last)) return `${name}:s`;
  return `${name}s`;
}

const capitalised = (text: string) => (text ? text[0].toUpperCase() + text.slice(1) : text);

/**
 * The match's course, a sentence per event, as the app's report words it
 * for the same [variant]. [team] is ours; the opponent's name and where it
 * was played shape "gästerna" and "hemmalagets".
 */
export function matchStory(
  feed: LiveFeedItem[],
  context: { team: string; opponent?: string | null; homeAway?: string | null; variant?: number; words?: Wordings },
): string[] {
  const words = context.words ?? wordings;
  const team = context.team;
  const opponent = context.opponent?.trim() || "Motståndaren";
  const variant = context.variant ?? 0;
  const [ourOwner, theirSide, theirOwner] =
    context.homeAway === "home" ? ["hemmalagets", "gästerna", "gästernas"]
      : context.homeAway === "away" ? ["bortalagets", "hemmalaget", "hemmalagets"]
        : [owner(team), opponent, owner(opponent)];

  // Each kind of sentence takes its wordings in turn, from the variant;
  // without a player, never a wording naming both player and team.
  const used = new Map<string, number>();
  const pick = (group: string, list: string[], named = true) => {
    const fitting = named ? list : list.filter(w => !(w.includes("{p}") && w.includes("{t}")));
    const choices = fitting.length ? fitting : list;
    const turn = (used.get(group) ?? -1) + 1;
    used.set(group, turn);
    return choices[(variant + turn) % choices.length];
  };
  const fill = (template: string, values: { minute: number; player?: string | null; keeper?: string | null; save?: boolean; assist?: string; on?: string; off?: string; score?: string }) => {
    let text = template;
    if (values.save) {
      text = values.keeper == null
        ? text.replaceAll("{tg} målvakt {p}", "{tg} målvakt").replaceAll("{p} i målet", "målvakten").replaceAll("{p}", "målvakten")
        : text.replaceAll("{p}", values.keeper);
    } else if (values.player == null) {
      text = text.replaceAll("{tg} {p}", "{t}").replaceAll("{p}", "{t}");
    }
    return capitalised(text
      .replaceAll("{a}", values.assist ?? "")
      .replaceAll("{p}", values.player ?? team)
      .replaceAll("{tg}", ourOwner)
      .replaceAll("{t}", team)
      .replaceAll("{og}", theirOwner)
      .replaceAll("{od}", theirSide)
      .replaceAll("{o}", opponent)
      .replaceAll("{in}", values.on ?? "")
      .replaceAll("{out}", values.off ?? "")
      .replaceAll("{s}", values.score ?? "")
      .replaceAll("{home}", "")
      .replaceAll("{min}", ordinal(values.minute))
      .replaceAll("{n}", `${values.minute}`));
  };

  const story: string[] = [];
  let us = 0, them = 0;
  for (const item of [...feed].sort((a, b) => a.n - b.n)) {
    const mine = item.side !== "opponent";
    const who = item.player ?? null;
    const minute = item.minute ?? 0;
    switch (item.type) {
      case "goal": {
        const lead = mine ? us - them : them - us;
        if (mine) us++; else them++;
        const situation = lead === 0 ? "lead" : lead > 0 ? "extend" : lead === -1 ? "equalise" : "reduce";
        const score = `${us}–${them}`;
        story.push(mine
          ? fill(pick(`goal-${situation}`, (words.goalsUs as Grouped)[situation], who != null), {
              minute, player: who, score,
              assist: item.second ? pick("assist", words.assists).replaceAll("{a}", item.second) : undefined,
            })
          : fill(pick(`goal-them-${situation}`, (words.goalsThem as Grouped)[situation]), { minute, score }));
        break;
      }
      case "shot": {
        const result = item.result ?? "missed";
        const lists = (mine ? words.shotsUs : words.shotsThem) as Grouped;
        story.push(fill(pick(`shot-${mine}-${result}`, lists[result] ?? lists.missed, !mine || who != null), { minute, player: who }));
        break;
      }
      case "save":
        if (mine) story.push(fill(pick("save", words.saves), { minute, keeper: who, save: true }));
        break;
      case "penalty": {
        const lists = (mine ? words.penaltiesUs : words.penaltiesThem) as Grouped;
        const list = lists[item.result ?? "scored"];
        if (list) story.push(fill(pick(`penalty-${mine}-${item.result ?? "scored"}`, list, !mine || who != null), { minute, player: who }));
        break;
      }
      case "card": {
        const lists = (mine ? words.cardsUs : words.cardsThem) as Grouped;
        const list = item.result ? lists[item.result] : undefined;
        if (list) story.push(fill(pick(`card-${mine}-${item.result}`, list, !mine || who != null), { minute, player: who }));
        break;
      }
      case "substitution":
        // Without a name for both, a substitution says nothing public.
        if (mine && item.player && item.second) {
          story.push(fill(pick("substitution", words.substitutions), { minute, player: who, on: item.second, off: item.player }));
        }
        break;
      case "injury":
        if (mine) story.push(fill(pick("injury", words.injuries, who != null), { minute, player: who }));
        break;
    }
  }
  return story;
}

/** A stable variant per match, so matches are worded differently. */
export function variantFor(matchId: string): number {
  let sum = 0;
  for (const char of matchId) sum = (sum + char.charCodeAt(0)) % 997;
  return sum;
}

/** Seconds played, as the app's match clock counts them. */
export function elapsedSeconds(clock: LiveClock, now: Date): number {
  const started = clock.started_at ? Date.parse(clock.started_at) : NaN;
  if (Number.isNaN(started)) return 0;
  const stopped = clock.completed_at ?? clock.paused_at;
  const end = stopped ? Date.parse(stopped) : now.getTime();
  let elapsed = Math.floor((end - started) / 1000) - (clock.paused_seconds ?? 0);
  if (elapsed < 0) elapsed = 0;
  const scheduled = clock.period_end?.scheduled_minute, actual = clock.period_end?.elapsed_seconds;
  if (scheduled != null && actual != null && scheduled * 60 - actual > 0) elapsed += scheduled * 60 - actual;
  return elapsed;
}

/** "34:12 · 1:a halvlek", "Halvtid", "Slutresultat". */
export function clockLabel(match: Pick<LiveMatch, "state" | "clock">, now: Date): { time: string; phase: string } {
  const seconds = elapsedSeconds(match.clock, now);
  const time = `${String(Math.floor(seconds / 60)).padStart(2, "0")}:${String(seconds % 60).padStart(2, "0")}`;
  if (match.state === "completed") return { time, phase: "Slutresultat" };
  const periods = match.clock.period_minutes?.length ?? 2;
  const period = match.clock.current_period ?? 1;
  const name = periods === 2 ? `${period}:a halvlek` : periods === 1 ? "Matchen" : `Period ${period}`;
  if (match.clock.period_ended) return { time, phase: periods === 2 && period === 1 ? "Halvtid" : `Paus efter period ${period}` };
  return { time, phase: match.clock.paused_at ? `${name} · pausad` : name };
}
