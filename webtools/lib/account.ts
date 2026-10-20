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

/** Sign-in and sign-up input, checked before anything is sent. */
export function validCredentials(address: string, password: string, signUp: boolean): string | null {
  if (!email.test(address.trim())) return "Skriv en giltig e-postadress.";
  if (signUp && (password.length < 8 || password.length > 128)) return "Lösenordet behöver vara minst 8 tecken.";
  if (!signUp && password.length === 0) return "Skriv ditt lösenord.";
  return null;
}
