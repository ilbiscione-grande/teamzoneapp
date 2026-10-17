import { serverConfig, siteOrigins } from "../../../../../lib/config";
import { json, neutralError } from "../../../../../lib/http";
import { placeFromNominatim, type Place } from "../../../../../lib/match-pool";
import { createServerSupabase } from "../../../../../lib/supabase-admin";

// POOL-01: place search for the match pool (a team's starting point or a
// listing's place). Only for signed-in users, on explicit search, at most
// one request per second to OpenStreetMap's Nominatim (its usage policy),
// cached, and only Swedish places. Positions are rounded to about a km.

export const dynamic = "force-dynamic";

const cache = new Map<string, { at: number; places: Place[] }>();
const perUser = new Map<string, number[]>();
let queue: Promise<unknown> = Promise.resolve();
let lastCall = 0;

function throttled<T>(task: () => Promise<T>): Promise<T> {
  const run = queue.then(async () => {
    const wait = lastCall + 1100 - Date.now();
    if (wait > 0) await new Promise(resolve => setTimeout(resolve, wait));
    lastCall = Date.now();
    return task();
  });
  queue = run.catch(() => undefined);
  return run;
}

export async function GET(request: Request) {
  try {
    const config = serverConfig(true);
    const origin = request.headers.get("origin");
    if (origin && !siteOrigins(config).includes(origin)) return json({ error: "Begäran kunde inte behandlas." }, 403);
    const token = /^Bearer\s+(\S+)$/i.exec(request.headers.get("authorization") ?? "")?.[1];
    if (!token) return json({ error: "Logga in för att söka platser." }, 401);
    const { data, error } = await createServerSupabase(config).auth.getUser(token);
    if (error || !data.user) return json({ error: "Logga in för att söka platser." }, 401);

    const query = (new URL(request.url).searchParams.get("q") ?? "").trim().replace(/\s+/g, " ");
    if (query.length < 2 || query.length > 100) return json({ error: "Skriv minst två tecken." }, 400);
    const now = Date.now();
    const recent = (perUser.get(data.user.id) ?? []).filter(at => at > now - 10 * 60000);
    if (recent.length >= 30) return json({ error: "För många sökningar. Försök igen om en stund." }, 429);
    perUser.set(data.user.id, [...recent, now]);

    const cacheKey = query.toLowerCase();
    const cached = cache.get(cacheKey);
    if (cached && cached.at > now - 24 * 3600000) return json({ places: cached.places });

    const url = new URL("https://nominatim.openstreetmap.org/search");
    url.search = new URLSearchParams({ q: query, format: "jsonv2", countrycodes: "se", limit: "6", addressdetails: "1", "accept-language": "sv" }).toString();
    const response = await throttled(() => fetch(url, {
      headers: { "User-Agent": "TeamZone-matchpool/1.0 (+https://teamzoneapp.se)", Referer: "https://teamzoneapp.se/matchpool" },
      signal: AbortSignal.timeout(8000),
    }));
    if (!response.ok) return json({ error: "Platssökningen svarar inte just nu. Försök igen." }, 503);
    const results = await response.json() as Parameters<typeof placeFromNominatim>[0][];
    const byLabel = new Map<string, Place>();
    for (const place of (Array.isArray(results) ? results : []).map(placeFromNominatim)) {
      if (place && !byLabel.has(place.place_label)) byLabel.set(place.place_label, place);
    }
    const places = [...byLabel.values()];
    if (cache.size > 1000) cache.clear();
    cache.set(cacheKey, { at: now, places });
    return json({ places });
  } catch (error) {
    return neutralError(error);
  }
}
