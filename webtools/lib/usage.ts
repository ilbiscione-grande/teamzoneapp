// Usage counts for TeamZone support (2026-11-14): which pages are visited,
// which ready boards, templates and library items are used, and who has
// Webtools open right now. Pages are counted by their pattern, never an
// address with ids or codes; nothing here says who did it.
import type { SupabaseClient } from "@supabase/supabase-js";

export type UseKind = "page" | "starter" | "template" | "shared";

/** The app's routes; a segment in brackets stands for any value. */
const routes = [
  "/appar/[slug]", "/aviseringar", "/bokningar", "/bokningar/[org]", "/delad/mapp/[token]", "/delad/[token]",
  "/konto", "/live", "/live/[code]", "/logga-in", "/support/tacticsboard", "/support/tacticsboard/[guide]",
  "/tacticsboard", "/tacticsboard/bibliotek", "/tacticsboard/demo", "/tacticsboard/granska",
  "/tacticsboard/mapp/[id]", "/tacticsboard/[id]", "/turnering/[id]", "/turneringar", "/turneringar/[id]",
].map(route => route.split("/").slice(1));

/** The route a path belongs to, or "other"; a fixed segment wins over one in brackets. */
export function pagePattern(path: string): string {
  const parts = path.split("?")[0].split("#")[0].replace(/\/+$/, "").split("/").slice(1);
  if (parts.length === 0 || (parts.length === 1 && parts[0] === "")) return "/";
  let best: string[] | null = null, bestFixed = -1;
  for (const route of routes) {
    if (route.length !== parts.length) continue;
    let fixed = 0, fits = true;
    route.forEach((segment, index) => {
      if (segment.startsWith("[")) return;
      if (segment === parts[index]) fixed++; else fits = false;
    });
    if (fits && fixed > bestFixed) { best = route; bestFixed = fixed; }
  }
  return best ? `/${best.join("/")}` : "other";
}

/** Counts one use; a failure is ignored, the count only helps support. */
export function recordUse(client: SupabaseClient | null, kind: UseKind, key: string): void {
  if (!client) return;
  void client.schema("api").rpc("record_webtools_use", { kind, key }).then(() => undefined, () => undefined);
}

/** Which app a page belongs to in TeamZone's statistics. */
export function appFor(pattern: string): "tacticsboard" | "webtools" {
  return /^\/(tacticsboard|live|delad|support\/tacticsboard)(\/|$)/.test(pattern) ? "tacticsboard" : "webtools";
}

const appsToday = new Set<string>();

/**
 * Counts the account as active today in this app, once a day per tab.
 * Only where Webtools shares TeamZone's database: the Tacticsboard-only
 * site has its own, and its customers are counted in its own statistics.
 */
export function recordAppActivity(client: SupabaseClient | null, app: "tacticsboard" | "webtools", today = new Date()): boolean {
  const key = `${today.toLocaleDateString("sv-SE", { timeZone: "Europe/Stockholm" })}:${app}`;
  if (!client || appsToday.has(key)) return false;
  appsToday.add(key);
  void client.schema("api").rpc("record_app_activity", { app }).then(() => undefined, () => undefined);
  return true;
}

/** Says this tab is open; a failure is ignored. */
export function recordPresence(client: SupabaseClient | null): void {
  if (!client) return;
  void client.schema("api").rpc("record_webtools_presence").then(() => undefined, () => undefined);
}
