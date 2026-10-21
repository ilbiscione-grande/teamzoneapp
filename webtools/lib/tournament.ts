// Turneringsplaneraren: shapes from the tournament API and pure helpers.

export type TournamentStatus = "draft" | "published" | "finished" | "cancelled";
export type TournamentRole = "organizer" | "official";
export type ClassFormat = "groups_playoff" | "pool";
export type RegistrationStatus = "pending" | "approved" | "declined" | "withdrawn";

export type TournamentSummary = {
  id: string;
  name: string;
  sport: string | null;
  location: string | null;
  starts_on: string;
  ends_on: string;
  status: TournamentStatus;
  registration_open: boolean;
  role: TournamentRole | "participant";
  /** For organisers: registrations waiting for a decision. */
  pending: number | null;
};

export type TournamentClass = {
  id: string;
  name: string;
  description: string | null;
  format: ClassFormat;
  max_teams: number | null;
  fee_sek: number | null;
  match_minutes: number | null;
  sort_order: number;
  approved: number;
  pending: number;
};

export type Registration = {
  id: string;
  class_id: string;
  class_name: string;
  team_name: string;
  club_name: string | null;
  contact_name: string;
  contact_email: string;
  contact_phone: string | null;
  notes: string | null;
  status: RegistrationStatus;
  paid: boolean;
  is_mine: boolean;
  /** Staff only. */
  registered_by_name: string | null;
  teamzone_team_id: string | null;
  created_at: string;
};

export type StaffMember = { profile_id: string; name: string | null; role: TournamentRole; is_self: boolean };

export type Tournament = {
  id: string;
  name: string;
  sport: string | null;
  location: string | null;
  starts_on: string;
  ends_on: string;
  description: string | null;
  contact_email: string | null;
  payment_info: string | null;
  status: TournamentStatus;
  registration_open: boolean;
  registration_closes_at: string | null;
  /** Published, open, and before the closing time. */
  registration_is_open: boolean;
  role: TournamentRole | null;
  organizer_name: string | null;
  classes: TournamentClass[];
  my_registrations: Registration[];
  /** Organisers only. */
  staff: StaffMember[] | null;
};

export const tournamentStatusLabels: Record<TournamentStatus, string> = {
  draft: "Utkast",
  published: "Publicerad",
  finished: "Avslutad",
  cancelled: "Inställd",
};

export const formatLabels: Record<ClassFormat, string> = {
  groups_playoff: "Gruppspel och slutspel",
  pool: "Poolspel utan tabell",
};

export const registrationStatusLabels: Record<RegistrationStatus, string> = {
  pending: "Väntar på godkännande",
  approved: "Godkänd",
  declined: "Nekad",
  withdrawn: "Återtagen",
};

export const roleLabels: Record<TournamentRole | "participant", string> = {
  organizer: "Arrangör",
  official: "Funktionär",
  participant: "Anmält lag",
};

const errorMessages: Record<string, string> = {
  invalid_dates: "Kontrollera datumen: slutdatumet kan inte vara före startdatumet, och en turnering är högst en månad.",
  invalid_status: "Okänd status.",
  has_registrations: "Det finns redan anmälningar. Ställ in turneringen i stället, eller ta bort anmälningarna först.",
  not_organizer: "Det kräver att du är arrangör för turneringen.",
  not_found: "Hittades inte, eller så har du inte tillgång.",
  class_name_taken: "Det finns redan en klass med det namnet.",
  invalid_format: "Okänt spelformat.",
  registration_closed: "Anmälan är stängd.",
  invalid_email: "Skriv en giltig e-postadress.",
  class_full: "Klassen är full.",
  team_name_taken: "Ett lag med det namnet är redan anmält i klassen.",
  not_active: "Anmälan är redan återtagen eller avgjord.",
  not_pending: "Anmälan är redan hanterad.",
  invitation_invalid: "Inbjudan gäller inte längre. Be om en ny länk.",
  invalid_role: "Okänd roll.",
  last_organizer: "Turneringen behöver minst en arrangör.",
  not_signed_in: "Logga in först.",
};

export function tournamentError(error: { message?: string } | null | undefined): string {
  return errorMessages[error?.message ?? ""] ?? "Det gick inte. Försök igen.";
}

const day = (value: string) => {
  const [y, m, d] = value.split("-").map(Number);
  return new Date(y, m - 1, d);
};

/** "14–15 nov. 2026", "30 nov.–1 dec. 2026" or "14 nov. 2026". */
export function dateSpan(startsOn: string, endsOn: string): string {
  const start = day(startsOn), end = day(endsOn);
  const year = end.getFullYear();
  const dayMonth = (value: Date) => value.toLocaleDateString("sv-SE", { day: "numeric", month: "short" });
  if (startsOn === endsOn) return `${dayMonth(start)} ${year}`;
  if (start.getMonth() === end.getMonth() && start.getFullYear() === end.getFullYear()) {
    return `${start.getDate()}–${dayMonth(end)} ${year}`;
  }
  return `${dayMonth(start)}${start.getFullYear() === year ? "" : ` ${start.getFullYear()}`}–${dayMonth(end)} ${year}`;
}

/** "1 500 kr", or null without a fee. */
export function feeLabel(fee: number | null): string | null {
  if (fee === null) return null;
  if (fee === 0) return "Ingen avgift";
  return `${fee.toLocaleString("sv-SE")} kr`;
}

/** Places left in a class, or null when it has no limit. */
export function placesLeft(item: TournamentClass): number | null {
  return item.max_teams === null ? null : Math.max(0, item.max_teams - item.approved);
}

/** A staff invitation token from a pasted link or the bare token. */
export function staffInvitationToken(value: string): string | null {
  const match = /([0-9a-f]{64})/.exec(value.trim());
  return match ? match[1] : null;
}

/** Registrations grouped by class in the classes' order, each class once. */
export function registrationsByClass(classes: TournamentClass[], registrations: Registration[]): { item: TournamentClass; registrations: Registration[] }[] {
  return [...classes]
    .sort((a, b) => a.sort_order - b.sort_order || a.name.localeCompare(b.name, "sv"))
    .map(item => ({ item, registrations: registrations.filter(registration => registration.class_id === item.id) }));
}

/** A whole number of kronor or minutes from a form field; "" is none. */
export function wholeNumber(value: string, min: number, max: number): number | null | "invalid" {
  const trimmed = value.replace(/\s/g, "");
  if (!trimmed) return null;
  const number = Number(trimmed);
  return Number.isInteger(number) && number >= min && number <= max ? number : "invalid";
}
