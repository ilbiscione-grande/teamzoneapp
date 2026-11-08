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

export type ResourceOwnership = "unspecified" | "owned" | "external";

export type ResourceWindow = { start: number; end: number };
export type ResourceAvailability = {
  mode: "always" | "weekly";
  weekly: (ResourceWindow & { day: number })[];
  exceptions: { date: string; windows: ResourceWindow[] }[];
};

export type Resource = {
  parent_resource_id?: string | null;
  availability?: ResourceAvailability;
  id: string;
  revision?: number;
  ownership_kind?: ResourceOwnership;
  owner_name?: string | null;
  timezone?: string;
  available_from?: string | null;
  available_until?: string | null;
  pitch_layout?: Record<string,string> | null;
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
  revision: number;
  revisions: Record<string, number>;
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
  can_move_event?: boolean;
  future_plan_id?: string | null;
  resource_event_series?: boolean;
  event_starts_at?: string | null;
  event_ends_at?: string | null;
  can_decide: boolean;
  /** A recurring booking: its series and how many coming times are left. */
  series_id?: string | null;
  series_sequence?: number | null;
  series_forward_remaining?: number;
  series_upcoming_remaining?: number;
  event_upcoming_remaining?: number;
  event_forward_remaining?: number;
  series_remaining?: number | null;
  /** Booked together with other resources: the group and its resources. */
  group_id?: string | null;
  group_resources?: string[] | null;
};

export type SeriesOverride = { original_starts_at: string; starts_at: string; ends_at: string; resource_ids: string[] };
export type SeriesTime = { starts_at: string; ends_at: string; clash: boolean; outside_disposition?: boolean;
  original_starts_at?: string; resource_ids?: string[]; changed?: boolean;
  blocked_resources?: { resource_id: string; name: string; outside_disposition: boolean }[] };

/** A planned or booked series: every time, and whether it clashes. */
export type SeriesPlan = {
  series_id: string | null;
  status: "pending" | "confirmed";
  created: number;
  times: SeriesTime[];
};

export const weekdayLabels = ["Mån", "Tis", "Ons", "Tor", "Fre", "Lör", "Sön"];

/** ISO weekday of a local date key: 1 for Monday to 7 for Sunday. */
export function isoWeekday(key: string): number {
  const [y, m, d] = key.split("-").map(Number);
  return ((new Date(y, m - 1, d).getDay() + 6) % 7) + 1;
}

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
  activity_link_not_standalone: "Bara kommande, aktiva bokningar utan aktivitetskoppling kan kopplas. Ladda om bokningen.",
  activity_resource_already_booked: "Aktiviteten har redan en aktiv bokning av någon av resurserna. Hantera den befintliga bokningen först.",
  series_plan_requires_combined: "Serien har en seriegrund. Använd Ändra tid och resurser så att även nya framtida tillfällen följer ändringen.",
  series_plan_multiple_organizations: "Aktivitetsserien har resurser från flera organisationer. Den kan inte genereras från en enda organisations seriegrund.",
  generation_failed: "Tillfället kunde inte skapas. Kontrollera seriegrunden och försök igen.",
  past_occurrence: "Tillfället har passerat och skapas inte i efterhand.",
  booking_change_conflicts: "Tiden eller någon resurs är inte tillgänglig. Ingen ändring har sparats. Förhandsvisa igen.",
  booking_change_no_change: "Ingen tid eller resurs behöver ändras med dina val.",
  pitch_layout_exists: "Planen har redan delar. Använd den befintliga indelningen eller kontakta administratören för hjälp med upplägget.",
  invalid_resource_set: "Välj vilka resurser som ska läggas till och tas bort. Samma resurs kan inte väljas i båda listorna.",
  too_many_resources: "En bokning kan ha högst tio aktiva resurser. Ta bort någon resurs först.",
  resource_set_conflicts: "Något tillfälle kan inte ändras. Ingen ändring har sparats. Förhandsvisa igen för att se aktuella konflikter.",
  resource_set_no_change: "Inga resurser behöver ändras med dina val.",
  resource_series_ambiguous: "Ett tillfälle har flera separata bokningar av ursprungsresursen. Byt dem var för sig för att undvika ett otydligt seriebyte.",
  resource_change_requires_future: "Resurs kan bara bytas för ett tillfälle som inte har börjat.",
  resource_change_not_found: "Välj en resurs i samma organisation.",
  resource_change_same: "Välj en annan resurs än den som redan är bokad.",
  resource_change_conflicts: "Den nya resursen kan inte bokas. Din befintliga bokning är kvar. Förhandsvisa igen för att se aktuella konflikter.",
  forward_conflicts: "Ett tillfälle kan inte flyttas. Ingen ändring har sparats. Förhandsvisa igen för att se de aktuella konflikterna.",
  forward_requires_future: "Välj ett tillfälle som inte har börjat. Pågående och tidigare tillfällen flyttas inte med serien.",
  forward_series_not_found: "Det här tillfället hör inte till en serie som kan flyttas här.",
  forward_invalid_local_time: "En av tiderna är ogiltig eller tvetydig vid övergången mellan sommar- och vintertid. Välj en annan klocktid och förhandsvisa igen.",
  event_move_not_allowed: "Du saknar behörighet att ändra aktiviteten. Du kan ändra bara resursens bokningstid.",
  event_booking_conflict: "Någon av aktivitetens resurser är upptagen. Hela ändringen har stoppats.",
  event_booking_outside_hours: "Någon av aktivitetens resurser är inte tillgänglig under den nya tiden.",
  event_booking_inactive: "Någon av aktivitetens resurser är inaktiverad.",
  event_booking_invalid_time: "Kontrollera tiderna för aktiviteten och alla dess bokningar.",
  invalid_timezone: "Ange en giltig tidszon, till exempel Europe/Stockholm.",
  invalid_resource_hierarchy: "Välj en överordnad resurs i samma organisation. En resurs kan inte vara del av sig själv eller någon av sina underdelar.",
  hierarchy_has_bookings: "Indelningen kan inte ändras eftersom befintliga bokningar då skulle krocka eller hamna utanför tillåtna tider. Hantera bokningarna först.",
  invalid_availability: "Kontrollera veckotider och datumundantag. Sluttiden måste vara efter starttiden inom samma dag och varje undantagsdatum får bara förekomma en gång.",
  invalid_disposition: "Kontrollera ägare och dispositionsperiod. Slutdatum måste vara samma dag eller senare än startdatum.",
  disposition_has_bookings: "Tiderna kan inte ändras eftersom befintliga bokningar skulle hamna utanför. Hantera bokningarna först.",
  resource_outside_disposition: "Resursen får inte bokas utanför sina bokningsbara tider eller dispositionsperioden. Välj en annan tid.",
  stale_revision: "Bokningen har ändrats. Ladda om bokningarna och kontrollera dem igen.",
  revision_required: "Ladda om bokningarna innan du fortsätter.",
  idempotency_conflict: "Förfrågan har ändrats. Ladda om och försök igen.",
  resource_busy: "Resursen eller en överordnad/underordnad del är redan bokad den tiden. Välj en annan tid eller resurs.",
  in_the_past: "Tiden har redan passerat.",
  invalid_time: "Sluttiden behöver vara efter starttiden, och en bokning får vara högst 31 dagar.",
  resource_inactive: "Resursen går inte att boka just nu.",
  not_team_leader: "Du kan bara boka för lag där du är ledare.",
  event_changed: "Aktivitetens tid har ändrats. Ladda om aktiviteten och kontrollera tiderna innan du bokar.",
  event_not_found: "Aktiviteten hör inte till laget eller syns inte för dig.",
  event_needs_team: "Välj laget först när bokningen gäller en aktivitet.",
  not_admin: "Det kräver att du är administratör för organisationen.",
  not_club_admin: "Kopplingen kräver att du är administratör för klubben i TeamZone.",
  club_already_linked: "Klubben är redan kopplad till en annan organisation.",
  invitation_invalid: "Inbjudan gäller inte längre. Be om en ny länk.",
  not_found: "Hittades inte, eller så har du inte tillgång.",
  not_allowed: "Du kan inte ändra den här bokningen.",
  not_pending: "Bokningen är redan hanterad.",
  not_active: "Det finns inga kommande tillfällen kvar att avboka.",
  invalid_series: "Kontrollera upprepningen: minst en veckodag, ett slutdatum efter startdatumet och högst ett år.",
  series_too_long: "Serien blir för lång. Högst 200 tillfällen åt gången.",
};

export function bookingError(error: { message?: string } | null | undefined): string {
  const code = error?.message ?? "";
  return errorMessages[code] ?? "Det gick inte. Försök igen.";
}

/** Stable parent-before-child order, including inactive parents and malformed legacy roots. */
export function resourceTree(resources: Resource[]): {resource:Resource;depth:number}[] {
  const result:{resource:Resource;depth:number}[]=[],seen=new Set<string>();
  const visit=(resource:Resource,depth:number)=>{
    if(seen.has(resource.id))return;
    seen.add(resource.id);result.push({resource,depth});
    resources.filter(r=>r.parent_resource_id===resource.id).sort((a,b)=>a.name.localeCompare(b.name,"sv")).forEach(r=>visit(r,depth+1));
  };
  const sorted=[...resources].sort((a,b)=>a.name.localeCompare(b.name,"sv"));
  sorted.filter(r=>!r.parent_resource_id||!resources.some(p=>p.id===r.parent_resource_id)).forEach(r=>visit(r,0));
  sorted.forEach(r=>visit(r,0));
  return result;
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

// The calendar grid: hours from GRID_START to GRID_END, local time, unless
// the calendar's filter narrows them.
export const GRID_START = 6;
export const GRID_END = 24;

/** The hours a calendar shows, start inclusive, end exclusive (0–24). */
export type GridRange = { start: number; end: number };
export const defaultRange: GridRange = { start: GRID_START, end: GRID_END };

/** Monday of the week the day is in. */
export function weekStart(key: string): string {
  const [y, m, d] = key.split("-").map(Number);
  const weekday = (new Date(y, m - 1, d).getDay() + 6) % 7;
  return addDays(key, -weekday);
}

/**
 * Where a booking sits in one day's column, as fractions of the grid's hours;
 * null when it is not on that day. Parts outside the grid are cut at its
 * edges, and say so.
 */
export function gridPlacement(startsAt: string, endsAt: string, key: string, range: GridRange = defaultRange): { top: number; height: number; cutTop: boolean; cutBottom: boolean } | null {
  const grid0 = new Date(localInstant(key, `${String(range.start).padStart(2, "0")}:00`)).getTime();
  const grid1 = new Date(localInstant(range.end === 24 ? addDays(key, 1) : key, range.end === 24 ? "00:00" : `${String(range.end).padStart(2, "0")}:00`)).getTime();
  const start = new Date(startsAt).getTime();
  const end = new Date(endsAt).getTime();
  if (end <= grid0 || start >= grid1) return null;
  const from = Math.max(start, grid0);
  const to = Math.min(end, grid1);
  const span = grid1 - grid0;
  return { top: (from - grid0) / span, height: Math.max((to - from) / span, 0.012), cutTop: start < grid0, cutBottom: end > grid1 };
}

/** A tap at a fraction of the grid as "HH:MM", on the half hour before it. */
export function slotAt(fraction: number, range: GridRange = defaultRange): string {
  const minutes = range.start * 60 + Math.floor((Math.min(Math.max(fraction, 0), 0.9999) * (range.end - range.start) * 60) / 30) * 30;
  return `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`;
}

/** "HH:MM" plus minutes, kept within the day. */
export function addMinutes(time: string, minutes: number): string {
  const [h, m] = time.split(":").map(Number);
  const total = Math.min(h * 60 + m + minutes, 23 * 60 + 59);
  return `${String(Math.floor(total / 60)).padStart(2, "0")}:${String(total % 60).padStart(2, "0")}`;
}

/** Where "now" is in the day's grid, or null outside it or another day. */
export function nowFraction(key: string, now = new Date(), range: GridRange = defaultRange): number | null {
  if (dateKey(now) !== key) return null;
  const hours = now.getHours() + now.getMinutes() / 60;
  if (hours < range.start || hours >= range.end) return null;
  return (hours - range.start) / (range.end - range.start);
}

/** What the calendar shows; null lists mean all. */
export type CalendarFilter = {
  resourceIds: string[] | null;
  /** Team ids, and "none" for bookings without a team. */
  teams: string[] | null;
  range: GridRange;
  onlyMine: boolean;
  onlyPending: boolean;
};

export const emptyFilter: CalendarFilter = { resourceIds: null, teams: null, range: defaultRange, onlyMine: false, onlyPending: false };

/** How many filters differ from showing everything. */
export function activeFilterCount(filter: CalendarFilter): number {
  return [
    filter.resourceIds !== null,
    filter.teams !== null,
    filter.range.start !== defaultRange.start || filter.range.end !== defaultRange.end,
    filter.onlyMine,
    filter.onlyPending,
  ].filter(Boolean).length;
}

/** Whether a booking matches the filter; those that do not are dimmed. */
export function matchesFilter(booking: Booking, filter: CalendarFilter): boolean {
  if (filter.onlyMine && !booking.is_mine) return false;
  if (filter.onlyPending && booking.status !== "pending") return false;
  if (filter.teams !== null && !filter.teams.includes(booking.team_id ?? "none")) return false;
  return true;
}

/** A stored filter, or nothing when it is unreadable or stale. */
export function parseFilter(value: string | null): CalendarFilter | null {
  if (!value) return null;
  try {
    const raw = JSON.parse(value) as Partial<CalendarFilter>;
    const list = (item: unknown) => Array.isArray(item) && item.every(entry => typeof entry === "string") ? item as string[] : null;
    const start = Number(raw.range?.start);
    const end = Number(raw.range?.end);
    const range = Number.isInteger(start) && Number.isInteger(end) && start >= 0 && end <= 24 && end - start >= 2 ? { start, end } : defaultRange;
    return { resourceIds: list(raw.resourceIds), teams: list(raw.teams), range, onlyMine: raw.onlyMine === true, onlyPending: raw.onlyPending === true };
  } catch {
    return null;
  }
}

/** Resource paths and descendant checks also tolerate partial legacy responses. */
export function resourcePath(resource: Resource, resources: Resource[]): string {
  const names = [resource.name];
  const seen = new Set([resource.id]);
  let parent = resource.parent_resource_id;
  while (parent && !seen.has(parent)) {
    seen.add(parent);
    const found = resources.find(item => item.id === parent);
    if (!found) break;
    names.unshift(found.name);
    parent = found.parent_resource_id;
  }
  return names.join(" → ");
}

export function resourceCanContain(parent: Resource, childId: string | null, resources: Resource[]): boolean {
  const seen = new Set<string>();
  let current: Resource | undefined = parent;
  while (current) {
    if (current.id === childId || seen.has(current.id)) return false;
    seen.add(current.id);
    current = resources.find(item => item.id === current?.parent_resource_id);
  }
  return true;
}
