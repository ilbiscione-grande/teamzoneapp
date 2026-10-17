// POOL-01 matchpoolen: types and pure helpers for the page. Everything is
// read and written through the api.*_match_pool RPCs as the signed-in leader.

export type PoolTeam = { team_id: string; team_name: string; club_name: string; verified: boolean; age_class: string | null; base: Place | null };
export type Place = { place_label: string; latitude: number; longitude: number };
export type Listing = {
  id: string; kind: "home_slot" | "away_wanted"; state: string; team_id: string; team_name: string; club_name: string; verified: boolean;
  starts_at: string | null; ends_at: string | null; date_from: string | null; date_to: string | null; max_distance_km: number | null;
  place_label: string; distance_km: number | null; venue_name: string | null; venue_surface: Surface | null; match_format: string;
  age_class: string; gender: Gender; level: Level | null; note: string | null; created_at: string;
  my_interest?: { id: string; state: InterestState } | null; current?: boolean; interests?: Interest[];
  can_republish?: boolean; republished?: boolean; own?: boolean;
};
export type InterestState = "pending" | "accepted" | "declined" | "withdrawn" | "closed" | "cancelled";
export type Interest = {
  id: string; listing_id: string; state: InterestState; team_id: string; team_name: string; club_name: string; verified: boolean;
  starts_at: string | null; ends_at: string | null; venue_name: string | null; venue_surface: Surface | null; add_to_calendar: boolean;
  unread: boolean; last_message: string | null; last_activity_at: string | null; created_at: string; listing?: Listing;
  cancel_requested_side?: "listing" | "interest" | null; cancel_requested_team_name?: string | null; cancel_reason?: string | null;
  cancel_requested_at?: string | null; cancelled_at?: string | null;
};
export type PoolPage = { teams: PoolTeam[]; origin: { team_id: string; place_label: string } | null; listings: Listing[]; mine: Listing[]; sent: Interest[]; watches?: Watch[] };
export type Watch = { id: string; team_id: string; team_name: string; kind: "all" | "home_slot" | "away_wanted"; max_distance_km: number;
  match_format: string | null; gender: Gender | null; age_class: string | null; verified_only: boolean; mine: boolean; created_at: string };
export type Conversation = {
  my_side: "listing" | "interest"; my_event_id: string | null; listing: Listing; interest: Interest;
  messages: { id: string; side: "listing" | "interest" | "system"; body: string; created_at: string; author_name: string | null }[];
};
export type Surface = "grass" | "artificial" | "indoor" | "other";
export type Gender = "boys" | "girls" | "mixed" | "men" | "women";
export type Level = "beginner" | "intermediate" | "advanced";

export const formats = ["3v3", "5v5", "7v7", "8v8", "9v9", "11v11"] as const;
export const formatLabel = (value: string) => value.replace("v", " mot ");
export const surfaceLabels: Record<Surface, string> = { grass: "Gräs", artificial: "Konstgräs", indoor: "Inomhus", other: "Annat" };
export const genderLabels: Record<Gender, string> = { boys: "Pojkar", girls: "Flickor", mixed: "Mixat", men: "Herrar", women: "Damer" };
export const levelLabels: Record<Level, string> = { beginner: "Nybörjare", intermediate: "Medel", advanced: "Stark" };
export const interestStateLabels: Record<InterestState, string> = {
  pending: "Väntar på svar", accepted: "Bokad", declined: "Nej tack", withdrawn: "Återkallad", closed: "Avslutad", cancelled: "Avbokad",
};

const zone = "Europe/Stockholm";
const dateFormat = new Intl.DateTimeFormat("sv-SE", { timeZone: zone, weekday: "short", day: "numeric", month: "short" });
const timeFormat = new Intl.DateTimeFormat("sv-SE", { timeZone: zone, hour: "2-digit", minute: "2-digit" });

/** "lör 14 mars kl 10:00–11:30" or "14 mars – 28 mars". */
export function whenLabel(listing: Pick<Listing, "kind" | "starts_at" | "ends_at" | "date_from" | "date_to">): string {
  if (listing.kind === "home_slot" && listing.starts_at && listing.ends_at) {
    return `${dateFormat.format(new Date(listing.starts_at))} kl ${timeFormat.format(new Date(listing.starts_at))}–${timeFormat.format(new Date(listing.ends_at))}`;
  }
  if (listing.date_from && listing.date_to) {
    const from = dateFormat.format(new Date(`${listing.date_from}T12:00:00Z`));
    const to = dateFormat.format(new Date(`${listing.date_to}T12:00:00Z`));
    return from === to ? from : `${from} – ${to}`;
  }
  return "";
}

export function slotLabel(starts: string | null, ends: string | null): string {
  if (!starts || !ends) return "";
  return `${dateFormat.format(new Date(starts))} kl ${timeFormat.format(new Date(starts))}–${timeFormat.format(new Date(ends))}`;
}

/** A local date and time in Stockholm ("2026-03-14", "10:00") as an instant. */
export function stockholmInstant(date: string, time: string): Date | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !/^\d{2}:\d{2}$/.test(time)) return null;
  const guess = new Date(`${date}T${time}:00Z`);
  if (Number.isNaN(guess.getTime())) return null;
  // The offset Stockholm has at that moment (CET or CEST).
  const parts = new Intl.DateTimeFormat("en-GB", { timeZone: zone, hour12: false, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" })
    .formatToParts(guess).reduce<Record<string, string>>((all, part) => ({ ...all, [part.type]: part.value }), {});
  const shown = Date.UTC(Number(parts.year), Number(parts.month) - 1, Number(parts.day), Number(parts.hour) % 24, Number(parts.minute));
  return new Date(guess.getTime() - (shown - guess.getTime()));
}

export function todayInStockholm(now = new Date()): string {
  return now.toLocaleDateString("sv-SE", { timeZone: zone });
}

export type Filters = { kind: "all" | "home_slot" | "away_wanted"; format: string; gender: string; verifiedOnly: boolean; text: string };
export const defaultFilters: Filters = { kind: "all", format: "", gender: "", verifiedOnly: false, text: "" };

export function filterListings(listings: Listing[], filters: Filters): Listing[] {
  const text = filters.text.trim().toLowerCase();
  return listings.filter(listing =>
    (filters.kind === "all" || listing.kind === filters.kind)
    && (!filters.format || listing.match_format === filters.format)
    && (!filters.gender || listing.gender === filters.gender)
    && (!filters.verifiedOnly || listing.verified)
    && (!text || `${listing.age_class} ${listing.team_name} ${listing.club_name} ${listing.place_label}`.toLowerCase().includes(text)));
}

export type ListingDraft = {
  kind: "home_slot" | "away_wanted"; date: string; startTime: string; endTime: string; dateFrom: string; dateTo: string;
  maxDistance: string; place: Place | null; venueName: string; surface: Surface | ""; format: string; ageClass: string;
  gender: Gender | ""; level: Level | ""; note: string;
};

/** The listing payload, or the first problem in Swedish. */
export function listingPayload(draft: ListingDraft, now = new Date()): { payload?: Record<string, unknown>; problem?: string } {
  if (!draft.place) return { problem: "Välj en ort för annonsen." };
  if (!draft.format) return { problem: "Välj spelform." };
  if (!draft.ageClass.trim()) return { problem: "Ange åldersklass, till exempel P12." };
  if (!draft.gender) return { problem: "Välj pojkar, flickor eller mixat." };
  if (draft.note.length > 500) return { problem: "Kommentaren får vara högst 500 tecken." };
  const common = {
    kind: draft.kind, place_label: draft.place.place_label, latitude: draft.place.latitude, longitude: draft.place.longitude,
    match_format: draft.format, age_class: draft.ageClass.trim(), gender: draft.gender, level: draft.level || null,
    note: draft.note.trim() || null,
  };
  if (draft.kind === "home_slot") {
    const starts = stockholmInstant(draft.date, draft.startTime);
    const ends = stockholmInstant(draft.date, draft.endTime);
    if (!starts || !ends) return { problem: "Ange datum och tid." };
    if (starts <= now) return { problem: "Tiden har redan passerat." };
    const minutes = (ends.getTime() - starts.getTime()) / 60000;
    if (minutes < 30 || minutes > 360) return { problem: "Matchtiden ska vara mellan 30 minuter och 6 timmar." };
    if (!draft.venueName.trim()) return { problem: "Ange plan eller anläggning." };
    return { payload: { ...common, starts_at: starts.toISOString(), ends_at: ends.toISOString(), venue_name: draft.venueName.trim(), venue_surface: draft.surface || null } };
  }
  const today = todayInStockholm(now);
  if (!draft.dateFrom || !draft.dateTo) return { problem: "Ange från och till vilket datum ni kan spela." };
  if (draft.dateFrom < today) return { problem: "Datumen har redan passerat." };
  if (draft.dateTo < draft.dateFrom) return { problem: "Slutdatumet är före startdatumet." };
  if ((Date.parse(draft.dateTo) - Date.parse(draft.dateFrom)) / 86400000 > 60) return { problem: "Datumintervallet får vara högst 60 dagar." };
  const distance = Number(draft.maxDistance);
  if (!Number.isInteger(distance) || distance < 5 || distance > 500) return { problem: "Ange hur långt ni kan resa, 5–500 km." };
  return { payload: { ...common, date_from: draft.dateFrom, date_to: draft.dateTo, max_distance_km: distance } };
}

export const poolErrors: Record<string, string> = {
  not_leader: "Matchpoolen är till för ledare. Den som får hantera kalendern i ett lag i TeamZone kan använda den.",
  rate_limited: "Du har gjort många ändringar på kort tid. Försök igen senare.",
  listing_closed: "Annonsen är inte längre öppen.",
  already_interested: "Ni har redan visat intresse för den här annonsen.",
  conversation_closed: "Konversationen är avslutad.",
  invalid_input: "Kontrollera uppgifterna och försök igen.",
  cancellation_pending: "Det finns redan en begäran om avbokning.",
  no_cancellation: "Det finns ingen begäran om avbokning längre.",
  not_booked: "Matchen är inte bokad.",
  cannot_republish: "Annonsen kan inte läggas ut igen, datumet har passerat.",
  no_base: "Välj lagets utgångsort först, så kan avståndet räknas.",
};

export function poolError(error: unknown): string {
  const message = typeof error === "object" && error && "message" in error ? String((error as { message: unknown }).message) : "";
  return Object.entries(poolErrors).find(([code]) => message.includes(code))?.[1] ?? "Något gick fel. Försök igen.";
}

/** Nominatim's answer reduced to a short place label and a rounded position. */
export function placeFromNominatim(item: { lat?: string; lon?: string; name?: string; display_name?: string;
  address?: Record<string, string | undefined> }): Place | null {
  const latitude = Number(item.lat), longitude = Number(item.lon);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;
  const address = item.address ?? {};
  const locality = address.city ?? address.town ?? address.village ?? address.suburb ?? address.hamlet ?? address.city_district;
  const municipality = address.municipality ?? address.county;
  const name = item.name && item.name !== locality ? item.name : undefined;
  const parts = [name, locality, municipality && municipality !== locality ? municipality.replace(/ kommun$/, "") : undefined]
    .filter((part): part is string => !!part && part.trim().length > 0);
  const label = (parts.length ? parts.join(", ") : (item.display_name ?? "").split(",").slice(0, 2).join(",")).trim().slice(0, 120);
  if (!label) return null;
  return { place_label: label, latitude: Math.round(latitude * 100) / 100, longitude: Math.round(longitude * 100) / 100 };
}

/** What a watch looks for, in words. */
export function watchLabel(watch: Pick<Watch, "kind" | "max_distance_km" | "match_format" | "gender" | "age_class" | "verified_only">): string {
  return [
    watch.kind === "home_slot" ? "Hemmatider" : watch.kind === "away_wanted" ? "Söker bortamatch" : "Alla annonser",
    `inom ${watch.max_distance_km} km`,
    watch.age_class, watch.match_format ? formatLabel(watch.match_format) : null,
    watch.gender ? genderLabels[watch.gender] : null,
    watch.verified_only ? "bara verifierade klubbar" : null,
  ].filter(Boolean).join(" · ");
}

export function newKey(): string {
  return crypto.randomUUID();
}
