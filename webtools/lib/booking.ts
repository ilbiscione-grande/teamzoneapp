// Bokningshanteraren: shapes from the booking API and pure helpers.

export type OrgRole = "admin" | "booker";

export type OrganizationSummary = {
  id: string;
  name: string;
  kind: OrgKind;
  sport: string | null;
  teamzone_club_id: string | null;
  teamzone_club_name: string | null;
  role: OrgRole;
};

export type OrgKind = "club" | "association" | "company" | "school" | "other";
export type ResourceCategory = "pitch" | "hall" | "locker_room" | "vehicle" | "equipment" | "room" | "other";

export type Resource = {
  id: string;
  name: string;
  category: ResourceCategory;
  description: string | null;
  location: string | null;
  capacity: number | null;
  requires_approval: boolean;
  active: boolean;
};

export type Member = { profile_id: string; name: string | null; role: OrgRole; is_self: boolean };

export type Organization = OrganizationSummary & {
  club_members_can_book: boolean;
  resources: Resource[];
  members: Member[] | null;
  teams: { team_id: string; name: string }[];
  pending_count: number | null;
};

export type BookingStatus = "pending" | "confirmed" | "declined" | "cancelled";

export type Booking = {
  id: string;
  resource_id: string;
  resource_name: string;
  starts_at: string;
  ends_at: string;
  title: string | null;
  notes: string | null;
  status: BookingStatus;
  booked_by_name: string | null;
  is_mine: boolean;
  team_id: string | null;
  team_name: string | null;
  event_id: string | null;
  event_title: string | null;
  can_cancel: boolean;
  can_decide: boolean;
};

export type TeamEvent = {
  event_id: string;
  title: string;
  event_type: string;
  starts_at: string;
  ends_at: string;
  home_away?: "home" | "away" | null;
  opponent_name?: string | null;
};

/** "P2012 – Aneby SK · Borta · lör 24 okt. 10:00": a match says home or away. */
export function eventOptionLabel(event: TeamEvent): string {
  const when = new Date(event.starts_at).toLocaleDateString("sv-SE", { weekday: "short", day: "numeric", month: "short" });
  const venue = event.home_away === "away" ? "Borta" : event.home_away === "home" ? "Hemma" : null;
  // The opponent, when the title does not already name it.
  const opponent = event.opponent_name && !event.title.includes(event.opponent_name) ? `mot ${event.opponent_name}` : null;
  return [event.title, opponent, venue, `${when} ${timeOf(event.starts_at)}`].filter(Boolean).join(" · ");
}

export const kindLabels: Record<OrgKind, string> = {
  club: "Idrottsklubb",
  association: "Förening",
  company: "Företag",
  school: "Skola",
  other: "Annat",
};

export const categoryLabels: Record<ResourceCategory, string> = {
  pitch: "Plan",
  hall: "Hall",
  locker_room: "Omklädningsrum",
  vehicle: "Fordon",
  equipment: "Utrustning",
  room: "Lokal",
  other: "Övrigt",
};

export const categoryOrder: ResourceCategory[] = ["pitch", "hall", "locker_room", "room", "vehicle", "equipment", "other"];

export const statusLabels: Record<BookingStatus, string> = {
  pending: "Väntar på godkännande",
  confirmed: "Bokad",
  declined: "Nekad",
  cancelled: "Avbokad",
};

/** The API's error codes as sentences; anything else is a general failure. */
const errorMessages: Record<string, string> = {
  resource_busy: "Resursen är redan bokad den tiden. Välj en annan tid eller resurs.",
  in_the_past: "Tiden har redan passerat.",
  invalid_time: "Sluttiden behöver vara efter starttiden, och en bokning får vara högst 31 dagar.",
  resource_inactive: "Resursen går inte att boka just nu.",
  not_team_leader: "Du kan bara boka för lag där du är ledare.",
  event_not_found: "Aktiviteten hör inte till laget eller syns inte för dig.",
  event_needs_team: "Välj laget först när bokningen gäller en aktivitet.",
  not_admin: "Det kräver att du är administratör för organisationen.",
  not_club_admin: "Kopplingen kräver att du är administratör för klubben i TeamZone.",
  club_already_linked: "Klubben är redan kopplad till en annan organisation.",
  invitation_invalid: "Inbjudan gäller inte längre. Be om en ny länk.",
  not_found: "Hittades inte, eller så har du inte tillgång.",
  not_allowed: "Du kan inte ändra den här bokningen.",
  not_pending: "Bokningen är redan hanterad.",
};

export function bookingError(error: { message?: string } | null | undefined): string {
  const code = error?.message ?? "";
  return errorMessages[code] ?? "Det gick inte. Försök igen.";
}

/** "2026-10-21" in local time. */
export function dateKey(value: Date): string {
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${value.getFullYear()}-${pad(value.getMonth() + 1)}-${pad(value.getDate())}`;
}

export function addDays(key: string, days: number): string {
  const [y, m, d] = key.split("-").map(Number);
  return dateKey(new Date(y, m - 1, d + days));
}

/** A local date and "HH:MM" as an ISO instant. */
export function localInstant(key: string, time: string): string {
  const [y, m, d] = key.split("-").map(Number);
  const [h, min] = time.split(":").map(Number);
  return new Date(y, m - 1, d, h, min).toISOString();
}

/** The local day's bounds as ISO instants. */
export function dayRange(key: string): { from: string; to: string } {
  return { from: localInstant(key, "00:00"), to: localInstant(addDays(key, 1), "00:00") };
}

export function timeOf(iso: string): string {
  return new Date(iso).toLocaleTimeString("sv-SE", { hour: "2-digit", minute: "2-digit" });
}

/** "10:00–12:00", with dates when it spans days. */
export function bookingSpan(startsAt: string, endsAt: string): string {
  const start = new Date(startsAt);
  const end = new Date(endsAt);
  if (dateKey(start) === dateKey(end)) return `${timeOf(startsAt)}–${timeOf(endsAt)}`;
  const day = (value: Date) => value.toLocaleDateString("sv-SE", { day: "numeric", month: "short" });
  return `${day(start)} ${timeOf(startsAt)} – ${day(end)} ${timeOf(endsAt)}`;
}

export function dayLabel(key: string): string {
  const [y, m, d] = key.split("-").map(Number);
  return new Date(y, m - 1, d).toLocaleDateString("sv-SE", { weekday: "long", day: "numeric", month: "long" });
}

/** Resources grouped by category in a stable order, active ones only. */
export function groupResources(resources: Resource[], includeInactive = false): { category: ResourceCategory; items: Resource[] }[] {
  return categoryOrder
    .map(category => ({
      category,
      items: resources
        .filter(resource => resource.category === category && (includeInactive || resource.active))
        .sort((a, b) => a.name.localeCompare(b.name, "sv")),
    }))
    .filter(group => group.items.length > 0);
}

/** An invitation link's token, from a pasted link or the bare token. */
export function invitationToken(value: string): string | null {
  const match = /([0-9a-f]{64})/.exec(value.trim());
  return match ? match[1] : null;
}
