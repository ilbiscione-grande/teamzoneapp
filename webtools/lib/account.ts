// Shapes read from TeamZone's API for the signed-in account. Webtools reads
// them with the user's own session; the server checks every call.

export type LegalStatus = {
  terms_version: string;
  terms_url: string;
  terms_accepted: boolean;
  privacy_version: string;
  privacy_url: string;
  privacy_accepted: boolean;
};

/** One of your roles in TeamZone: a team, or a whole club. */
export type Connection = {
  context_id: string;
  club_id: string;
  club_name: string;
  team_id: string | null;
  team_name: string | null;
  role_package: string;
};

export function requiresAcceptance(status: LegalStatus): boolean {
  return !status.terms_accepted || !status.privacy_accepted;
}

const roleLabels: Record<string, string> = {
  leader: "Ledare",
  player: "Spelare",
  guardian: "Vårdnadshavare",
  club_functionary: "Klubbfunktionär",
  guest: "Gäst",
  referee: "Domare",
  referee_assigner: "Domartillsättare",
};

export function roleLabel(role: string): string {
  return roleLabels[role] ?? role;
}

/** Your connections grouped by club, teams sorted, each team once. */
export function groupConnections(rows: Connection[]): { club: string; clubId: string; items: { name: string; roles: string[] }[] }[] {
  const clubs = new Map<string, { club: string; clubId: string; items: Map<string, { name: string; roles: Set<string> }> }>();
  for (const row of rows) {
    const club = clubs.get(row.club_id) ?? { club: row.club_name, clubId: row.club_id, items: new Map() };
    const name = row.team_name ?? "Hela klubben";
    const item = club.items.get(name) ?? { name, roles: new Set<string>() };
    item.roles.add(roleLabel(row.role_package));
    club.items.set(name, item);
    clubs.set(row.club_id, club);
  }
  return [...clubs.values()]
    .sort((a, b) => a.club.localeCompare(b.club, "sv"))
    .map(club => ({
      club: club.club,
      clubId: club.clubId,
      items: [...club.items.values()]
        .sort((a, b) => (a.name === "Hela klubben" ? -1 : b.name === "Hela klubben" ? 1 : a.name.localeCompare(b.name, "sv")))
        .map(item => ({ name: item.name, roles: [...item.roles] })),
    }));
}

const email = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/** What a new password needs, said under the field. */
export const passwordRule = "Minst 8 tecken med liten och stor bokstav, siffra och specialtecken, till exempel ! ? # %.";

// Supabase Auth's lower_upper_letters_digits_symbols: only these count as symbols.
const symbols = "!@#$%^&*()_+-=[]{};'\\:\"|<>?,./`~";

/** A new password against the auth rule, so the server never turns it down. */
function passwordProblem(password: string): string | null {
  if (password.length < 8 || password.length > 128) return "Lösenordet behöver vara minst 8 tecken.";
  const kinds = [/[a-z]/.test(password), /[A-Z]/.test(password), /[0-9]/.test(password), [...password].some(c => symbols.includes(c))];
  if (kinds.includes(false)) return "Lösenordet behöver liten och stor bokstav, siffra och specialtecken, till exempel ! ? # %.";
  return null;
}

/** Sign-in and sign-up input, checked before anything is sent. */
export function validCredentials(address: string, password: string, signUp: boolean): string | null {
  if (!email.test(address.trim())) return "Skriv en giltig e-postadress.";
  if (signUp) return passwordProblem(password);
  if (password.length === 0) return "Skriv ditt lösenord.";
  return null;
}

/** A new password, written twice: the same rule as when the account is made. */
export function validNewPassword(password: string, repeated: string): string | null {
  const problem = passwordProblem(password);
  if (problem) return problem;
  if (password !== repeated) return "Lösenorden är inte likadana.";
  return null;
}

/** The word that confirms ending the account (supabase/functions/account-deletion). */
export const deletionWord = "AVSLUTA";

/** The person's message when the account cannot be ended from Webtools. */
export function accountDeletionErrorText(code: string): string {
  if (code === "club_linked") {
    return "Ditt konto är kopplat till en klubb i TeamZone. Be om att få kontot raderat i TeamZone-appen, eller mejla support@teamzoneapp.se.";
  }
  if (code === "needs_support") {
    return "Kontot har uppgifter som behöver tas bort för hand. Mejla support@teamzoneapp.se så hjälper vi dig.";
  }
  if (code === "billing_cancel_failed") return "Prenumerationen gick inte att avsluta just nu. Inget är borttaget. Försök igen om en stund.";
  if (code === "not_signed_in") return "Logga in igen och försök på nytt.";
  return "Kontot går inte att avsluta just nu. Försök igen om en stund.";
}
