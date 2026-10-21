// The tournament's public page, read on Webtools' server with the secret
// key: the database lets only the server read it. Nothing here reaches the
// browser but the page.
import { createClient } from "@supabase/supabase-js";
import type { TournamentClass } from "./tournament";
import type { Pitch, ScheduleClass, ScheduleMatch } from "./tournament-schedule";

export type PublicTournament = {
  id: string;
  name: string;
  sport: string | null;
  location: string | null;
  starts_on: string;
  ends_on: string;
  description: string | null;
  contact_email: string | null;
  status: "published" | "finished";
  organizer_name: string | null;
  registration_is_open: boolean;
  registration_closes_at: string | null;
  classes: (TournamentClass & { teams: { team_name: string; club_name: string | null }[] })[];
  pitches: Pitch[];
  schedule: ScheduleClass[];
};

/** The page, or null when there is none (or the server cannot read it). */
export async function loadPublicTournament(id: string): Promise<PublicTournament | null> {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SECRET_KEY;
  if (!url || !key) return null;
  const client = createClient(url, key, {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
    global: { headers: { "X-Client-Info": "teamzone-webtools-server/0.1" } },
  });
  const { data, error } = await client.schema("api").rpc("get_public_tournament", { target_tournament_id: id });
  if (error) {
    console.error("public tournament", error.message);
    return null;
  }
  return (data as PublicTournament | null) ?? null;
}

const zone = "Europe/Stockholm";

/** "2026-11-14" in Swedish time, whatever the server's own zone. */
export function swedishDay(iso: string): string {
  return new Intl.DateTimeFormat("sv-SE", { timeZone: zone, year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date(iso));
}

export function swedishClock(iso: string): string {
  return new Intl.DateTimeFormat("sv-SE", { timeZone: zone, hour: "2-digit", minute: "2-digit" }).format(new Date(iso));
}

/** "lördag 14 november". */
export function swedishDayLabel(day: string): string {
  return new Intl.DateTimeFormat("sv-SE", { timeZone: "UTC", weekday: "long", day: "numeric", month: "long" }).format(new Date(`${day}T12:00:00Z`));
}

/** Matches by Swedish day in time order; those without a time last. */
export function publicMatchesByDay(matches: ScheduleMatch[]): { day: string | null; matches: ScheduleMatch[] }[] {
  const sorted = [...matches].sort((a, b) =>
    (a.starts_at === null ? 1 : 0) - (b.starts_at === null ? 1 : 0)
    || (a.starts_at ?? "").localeCompare(b.starts_at ?? "") || a.round - b.round || a.sort_order - b.sort_order);
  const days: { day: string | null; matches: ScheduleMatch[] }[] = [];
  for (const match of sorted) {
    const day = match.starts_at ? swedishDay(match.starts_at) : null;
    const last = days[days.length - 1];
    if (last && last.day === day) last.matches.push(match);
    else days.push({ day, matches: [match] });
  }
  return days;
}
