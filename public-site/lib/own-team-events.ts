export type TeamContext = { context_id: string; team_id: string | null; team_name: string | null; club_name: string };
export type OwnTeamEvent = { event_id: string; owning_team_id: string; team_name: string; title: string; event_type: "match" | "training" | "meeting" | "activity"; state: string; starts_at: string; ends_at: string; all_day: boolean; location_name?: string; event_cursor: string; match_state?: string; score_us?: number; score_opponent?: number };
type CalendarRow = Omit<OwnTeamEvent, "event_type"> & { event_type: string };
export type CalendarRpc = (name: string, params: Record<string, unknown>) => PromiseLike<{ data: unknown; error: unknown }>;

// The existing calendar RPC validates contexts and event audiences against the
// authenticated user. Following a public channel is never used for access.
export async function loadOwnTeamEvents(rpc: CalendarRpc, start: string, end: string) {
  const contexts = await rpc("get_my_contexts", {});
  if (contexts.error || !Array.isArray(contexts.data)) throw new Error("contexts_unavailable");
  const teams = (contexts.data as TeamContext[]).filter(context => context.team_id !== null);
  const teamIds = new Set(teams.map(context => context.team_id));
  const contextIds = [...new Set(teams.map(context => context.context_id))];
  const items = new Map<string, OwnTeamEvent>();
  for (let offset = 0; offset < contextIds.length; offset += 50) {
    let cursor: string | null = null;
    for (;;) {
      const result = await rpc("list_calendar_page", { context_ids: contextIds.slice(offset, offset + 50), range_start: start, range_end: end, page_cursor: cursor, page_limit: 200 });
      if (result.error || !Array.isArray(result.data)) throw new Error("calendar_unavailable");
      const rows = result.data as CalendarRow[];
      for (const row of rows) {
        if (teamIds.has(row.owning_team_id) && ["match", "training", "meeting", "activity"].includes(row.event_type) && ["scheduled", "completed"].includes(row.state)) {
          items.set(row.event_id, row as OwnTeamEvent);
        }
      }
      if (rows.length < 200) break;
      const next: string = rows[rows.length - 1].event_cursor;
      if (!next || next === cursor) throw new Error("invalid_calendar_cursor");
      cursor = next;
    }
  }
  return { hasTeams: teamIds.size > 0, teams: [...new Map(teams.map(team => [team.team_id, team])).values()], items: [...items.values()].sort((a,b) => a.starts_at.localeCompare(b.starts_at) || a.event_id.localeCompare(b.event_id)) };
}
