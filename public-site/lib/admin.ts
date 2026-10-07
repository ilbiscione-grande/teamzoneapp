// Page administration on the public site. Every command goes through the
// same authenticated api.* RPCs as the TeamZone app, which check the
// signed-in account's capabilities server side. This module only decides
// what to offer; it never grants access.

export type AdminRpc = (name: string, params: Record<string, unknown>) => PromiseLike<{ data: unknown; error: unknown }>;

export type AdminContext = {
  context_id: string;
  club_id: string;
  club_name: string;
  team_id: string | null;
  team_name: string | null;
  role_package?: string;
  capabilities?: string[];
};

export type SelfServiceItem = {
  id: string;
  name: string;
  slug: string;
  mode: "private" | "listed" | "published" | string;
  fields?: string[];
  locality?: string | null;
  description?: string | null;
  age_class?: string | null;
  revision?: number;
  request_status?: string | null;
  can_request?: boolean;
};

export type SelfService = {
  club: SelfServiceItem;
  teams?: SelfServiceItem[];
  requests?: { id: string; team_id?: string; team_name?: string; message?: string | null; status: string }[];
  can_manage_club?: boolean;
};

export type AdminTeam = { teamId: string; name: string; slug: string; canManage: boolean };

export type AdminScope = {
  clubId: string;
  clubName: string;
  /** Club page settings, team page decisions and partners. */
  canManageClub: boolean;
  /** The newsroom is club scoped, like the club page settings. */
  canPublishNews: boolean;
  /** Badge and colours belong to club administrators. */
  canManageBrand: boolean;
  teams: AdminTeam[];
};

const has = (context: AdminContext, capability: string) => (context.capabilities ?? []).includes(capability);

/** The clubs where the account could administer anything on the public pages. */
export function candidateClubIds(contexts: AdminContext[]): string[] {
  return [...new Set(contexts
    .filter(context => has(context, "publication.manage") || has(context, "team.roster.manage") || has(context, "club.memberships.manage"))
    .map(context => context.club_id))];
}

/**
 * Maps the public page's club slug to the account's rights in that club.
 * Returns null when the account administers nothing there.
 */
export function resolveAdminScope(clubSlug: string, contexts: AdminContext[], selfService: SelfService | null): AdminScope | null {
  if (!selfService?.club || selfService.club.slug !== clubSlug) return null;
  const clubId = selfService.club.id;
  const inClub = contexts.filter(context => context.club_id === clubId);
  if (!inClub.length) return null;
  const canManageClub = selfService.can_manage_club === true;
  const canManageBrand = inClub.some(context => has(context, "club.memberships.manage"));
  const manageableTeamIds = new Set(inClub
    .filter(context => context.team_id && (has(context, "publication.manage") || has(context, "team.roster.manage")))
    .map(context => context.team_id as string));
  const teams = (selfService.teams ?? []).map(team => ({
    teamId: team.id,
    name: team.name,
    slug: team.slug,
    canManage: canManageClub || manageableTeamIds.has(team.id),
  })).filter(team => team.canManage);
  const scope: AdminScope = {
    clubId,
    clubName: selfService.club.name,
    canManageClub,
    canPublishNews: canManageClub,
    canManageBrand,
    teams,
  };
  return scope.canManageClub || scope.canPublishNews || scope.canManageBrand || teams.length ? scope : null;
}

/** Loads the account's contexts and finds its rights for one club page. */
export async function loadAdminScope(rpc: AdminRpc, clubSlug: string): Promise<{ scope: AdminScope | null; contexts: AdminContext[]; selfService: SelfService | null }> {
  const contexts = await rpc("get_my_contexts", {});
  if (contexts.error || !Array.isArray(contexts.data)) throw new Error("contexts_unavailable");
  const list = contexts.data as AdminContext[];
  for (const clubId of candidateClubIds(list)) {
    const result = await rpc("get_publication_self_service", { club_id: clubId });
    if (result.error || !result.data) continue;
    const selfService = result.data as SelfService;
    const scope = resolveAdminScope(clubSlug, list, selfService);
    if (scope) return { scope, contexts: list, selfService };
  }
  return { scope: null, contexts: list, selfService: null };
}

/** Same rule as the app: Swedish letters folded, a–z, 0–9 and hyphens. */
export function suggestSlug(title: string, maxLength = 100): string {
  const folded = title.toLowerCase().trim().replace(/[åäöéèü]/g, letter =>
    ({ å: "a", ä: "a", ö: "o", é: "e", è: "e", ü: "u" } as Record<string, string>)[letter] ?? "");
  const slug = folded.replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
  return slug.length <= maxLength ? slug : slug.slice(0, maxLength).replace(/-+$/, "");
}

export function validSlug(value: string, min = 2, max = 100): boolean {
  return value.length >= min && value.length <= max && /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(value);
}

export type ArticleBlock = { type: string; text: string; href?: string };

/** Body text becomes one paragraph block per blank-line separated part. */
export function blocksFromText(body: string): ArticleBlock[] {
  return body.replace(/\r\n/g, "\n").split(/\n\s*\n/).map(part => part.trim()).filter(Boolean)
    .map(text => ({ type: "paragraph", text }));
}

export function textFromBlocks(blocks: ArticleBlock[] | undefined): string {
  return (blocks ?? []).map(block => block.text).filter(Boolean).join("\n\n");
}

export function validHexColor(value: string): boolean {
  return /^#[0-9a-fA-F]{6}$/.test(value.trim());
}

export function validPartnerUrl(value: string): boolean {
  if (!value.trim()) return true;
  try { return new URL(value.trim()).protocol === "https:"; } catch { return false; }
}

export function newIdempotencyKey(): string {
  return globalThis.crypto.randomUUID();
}

export const articleStateLabel: Record<string, string> = {
  draft: "Utkast",
  scheduled: "Schemalagd",
  published: "Publicerad",
  unpublished: "Avpublicerad",
};

export const publicationModeLabel: Record<string, string> = {
  private: "Privat",
  listed: "Endast i katalogen",
  published: "Publicerad",
};

export const requestStatusLabel: Record<string, string> = {
  pending: "Väntar på beslut",
  approved: "Godkänd",
  rejected: "Avslagen",
};

/** The fields a page publishes, in the order the app sends them. */
export function publicationFields(type: "club" | "team", mode: string, values: { locality?: string; description?: string; ageClass?: string; showLocality?: boolean; showDescription?: boolean; showAgeClass?: boolean }): string[] {
  if (mode === "private") return [];
  if (type === "club") {
    return ["name",
      ...(values.showLocality && values.locality?.trim() ? ["locality"] : []),
      ...(values.showDescription && values.description?.trim() ? ["description"] : [])];
  }
  return ["name", ...(values.showAgeClass && values.ageClass?.trim() ? ["age_class"] : [])];
}

/** A friendly message for an RPC failure, without leaking internals. */
export function adminErrorMessage(error: unknown, fallback = "Ändringen kunde inte sparas. Försök igen."): string {
  const message = typeof error === "object" && error && "message" in error ? String((error as { message: unknown }).message) : "";
  if (/stale_revision|serialization/.test(message)) return "Någon annan har ändrat detta. Ladda om och försök igen.";
  if (/slug|duplicate|unique/.test(message)) return "Webbadressen används redan eller är ogiltig.";
  if (/not_found|insufficient_privilege|permission|forbidden/.test(message)) return "Du saknar behörighet för den här åtgärden.";
  if (/club_not_published|publication_prerequisite/.test(message)) return "Klubbsidan måste vara publicerad först.";
  return fallback;
}
