import type { FeedItem } from "./personal-home";
import type { OwnTeamEvent } from "./own-team-events";

export type DashboardEvent = Pick<OwnTeamEvent, "event_id" | "title" | "starts_at" | "event_type" | "team_name" | "owning_team_id"> & { ends_at?: string; all_day?: boolean; location_name?: string; is_own: boolean; club_slug?: string; team_slug?: string };
export type DashboardItem = FeedItem & { is_own: boolean };
export type DashboardContent = { available: boolean; own_teams: { id: string; name: string; club_name: string; href: string | null }[]; news: DashboardItem[]; results: DashboardItem[]; events: DashboardEvent[]; calendar_truncated: boolean };

export function combineCalendar(published: DashboardEvent[], own: OwnTeamEvent[], now: Date): DashboardEvent[] {
  const end = now.getTime() + 90 * 86400000;
  const events = new Map<string, DashboardEvent>();
  for (const item of published) {
    if (item.event_type === "match" || item.event_type === "training") events.set(item.event_id, item);
  }
  for (const item of own) events.set(item.event_id, { ...item, is_own: true });
  return [...events.values()].filter(item => {
    const start = new Date(item.starts_at).getTime();
    const finish = new Date(item.ends_at ?? item.starts_at).getTime();
    return finish >= now.getTime() && start < end;
  }).sort((a,b) => a.starts_at.localeCompare(b.starts_at) || a.event_id.localeCompare(b.event_id));
}

export function combineResults(published: DashboardItem[], own: OwnTeamEvent[]): DashboardItem[] {
  const results = new Map(published.map(item => [item.id, item]));
  for (const item of own) {
    if (item.event_type !== "match" || item.match_state !== "completed" || item.score_us == null || item.score_opponent == null) continue;
    results.set(item.event_id, { ...results.get(item.event_id), id: item.event_id, kind: "result", happened_at: item.starts_at, title: item.title, team_name: item.team_name, club_name: "", club_slug: "", score_us: item.score_us, score_opponent: item.score_opponent, is_own: true });
  }
  return [...results.values()].sort((a,b) => b.happened_at.localeCompare(a.happened_at) || a.id.localeCompare(b.id));
}

export const eventLabels: Record<string, string> = { match: "Match", training: "Träning", meeting: "Möte", activity: "Aktivitet" };
export function dayKey(value: Date): string { return `${value.getFullYear()}-${String(value.getMonth()+1).padStart(2,"0")}-${String(value.getDate()).padStart(2,"0")}`; }

export type MatchReport = { state: string; written_report?: { body: string; published: boolean }; projection?: { score_us: number; score_opponent: number }; facts?: { id: string; state: string; fact_type: string; side?: string; minute: number; detail?: { result?: string; color?: string; delta?: number } }[] };
export function reportFacts(report: MatchReport) {
  return (report.facts ?? []).filter(fact => fact.state !== "voided" && ["goal", "card", "substitution", "half_time", "full_time", "period_end", "score_adjustment", "shot", "penalty", "free_kick", "corner"].includes(fact.fact_type)).filter(fact => !["shot", "penalty", "free_kick", "corner"].includes(fact.fact_type) || fact.detail?.result === "scored");
}
