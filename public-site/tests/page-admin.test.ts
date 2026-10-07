import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import test from "node:test";
import {
  adminErrorMessage, blocksFromText, candidateClubIds, loadAdminScope, publicationFields, resolveAdminScope,
  suggestSlug, textFromBlocks, validHexColor, validPartnerUrl, validSlug, type AdminContext, type AdminRpc, type SelfService,
} from "../lib/admin.ts";

const root = new URL("../", import.meta.url);
const ctx = (patch: Partial<AdminContext>): AdminContext => ({ context_id: "c", club_id: "club", club_name: "IFK", team_id: null, team_name: null, capabilities: [], ...patch });
const service = (patch: Partial<SelfService> = {}): SelfService => ({
  club: { id: "club", name: "IFK", slug: "ifk", mode: "published", revision: 3 },
  teams: [{ id: "f12", name: "F2012", slug: "f2012", mode: "published" }, { id: "p14", name: "P2014", slug: "p2014", mode: "private" }],
  requests: [], can_manage_club: false, ...patch,
});

test("only contexts that may administer something are looked up", () => {
  assert.deepEqual(candidateClubIds([
    ctx({ club_id: "a", capabilities: ["team.read"] }),
    ctx({ club_id: "b", capabilities: ["team.roster.manage"] }),
    ctx({ club_id: "c", capabilities: ["publication.manage"] }),
    ctx({ club_id: "c", context_id: "c2", capabilities: ["club.memberships.manage"] }),
  ]), ["b", "c"]);
});

test("a club publisher gets the newsroom, page settings, partners and every team", () => {
  const scope = resolveAdminScope("ifk", [ctx({ capabilities: ["publication.manage", "club.memberships.manage"] })], service({ can_manage_club: true }));
  assert.ok(scope);
  assert.equal(scope.canManageClub, true);
  assert.equal(scope.canPublishNews, true);
  assert.equal(scope.canManageBrand, true);
  assert.deepEqual(scope.teams.map(team => team.teamId), ["f12", "p14"]);
});

test("a team leader only gets their own team and no club-wide rights", () => {
  const scope = resolveAdminScope("ifk", [ctx({ team_id: "f12", team_name: "F2012", capabilities: ["team.roster.manage"] })],
    service({ teams: [{ id: "f12", name: "F2012", slug: "f2012", mode: "private", can_request: true }] }));
  assert.ok(scope);
  assert.equal(scope.canManageClub, false);
  assert.equal(scope.canPublishNews, false);
  assert.equal(scope.canManageBrand, false);
  assert.deepEqual(scope.teams.map(team => team.teamId), ["f12"]);
});

test("the page slug must match the club the rights belong to", () => {
  const contexts = [ctx({ capabilities: ["publication.manage"] })];
  assert.equal(resolveAdminScope("annan-klubb", contexts, service({ can_manage_club: true })), null);
  assert.equal(resolveAdminScope("ifk", [], service({ can_manage_club: true })), null);
  assert.equal(resolveAdminScope("ifk", contexts, null), null);
  // Reading rights is not enough to administer anything.
  assert.equal(resolveAdminScope("ifk", [ctx({ capabilities: ["team.read"] })], service({ teams: [] })), null);
});

test("loading rights asks the server per candidate club and stops at the matching slug", async () => {
  const calls: string[] = [];
  const rpc: AdminRpc = async (name, params) => {
    calls.push(`${name}:${String(params.club_id ?? "")}`);
    if (name === "get_my_contexts") return { data: [ctx({ club_id: "other", capabilities: ["publication.manage"] }), ctx({ club_id: "club", context_id: "c3", capabilities: ["publication.manage"] })], error: null };
    if (params.club_id === "other") return { data: service({ club: { id: "other", name: "Annan", slug: "annan", mode: "published" }, can_manage_club: true }), error: null };
    return { data: service({ can_manage_club: true }), error: null };
  };
  const result = await loadAdminScope(rpc, "ifk");
  assert.equal(result.scope?.clubId, "club");
  assert.equal(result.selfService?.club.slug, "ifk");
  assert.deepEqual(calls, ["get_my_contexts:", "get_publication_self_service:other", "get_publication_self_service:club"]);
  await assert.rejects(loadAdminScope(async () => ({ data: null, error: { message: "unauthenticated" } }), "ifk"), /contexts_unavailable/);
});

test("article slugs and paragraphs follow the app's rules", () => {
  assert.equal(suggestSlug("  Årets första möte! "), "arets-forsta-mote");
  assert.equal(suggestSlug("x".repeat(120)).length, 100);
  assert.equal(validSlug("arets-forsta-mote"), true);
  assert.equal(validSlug("Stora"), false);
  assert.equal(validSlug("a"), false);
  assert.equal(validSlug("f2014", 2, 80), true);
  const blocks = blocksFromText("Första stycket.\r\n\r\nAndra\nraden.\n\n\n");
  assert.deepEqual(blocks, [{ type: "paragraph", text: "Första stycket." }, { type: "paragraph", text: "Andra\nraden." }]);
  assert.equal(textFromBlocks(blocks), "Första stycket.\n\nAndra\nraden.");
});

test("published fields only include chosen, non-empty details", () => {
  assert.deepEqual(publicationFields("club", "private", { locality: "Vetlanda", showLocality: true }), []);
  assert.deepEqual(publicationFields("club", "published", { locality: "Vetlanda", showLocality: true, description: " ", showDescription: true }), ["name", "locality"]);
  assert.deepEqual(publicationFields("team", "published", { ageClass: "F12", showAgeClass: true }), ["name", "age_class"]);
});

test("colours, partner links and error messages are validated without leaking internals", () => {
  assert.equal(validHexColor("#00843d"), true);
  assert.equal(validHexColor("00843d"), false);
  assert.equal(validPartnerUrl(""), true);
  assert.equal(validPartnerUrl("https://partner.se"), true);
  assert.equal(validPartnerUrl("http://partner.se"), false);
  assert.match(adminErrorMessage({ message: "stale_revision" }), /ändrat/);
  assert.match(adminErrorMessage({ message: "not_found" }), /behörighet/);
  assert.equal(adminErrorMessage({ message: "internal relation core.x" }), "Ändringen kunde inte sparas. Försök igen.");
});

test("the admin page is never indexed and holds no data until sign-in", () => {
  const page = readFileSync(new URL("app/[clubSlug]/admin/page.tsx", root), "utf8");
  assert.match(page, /robots: \{ index: false, follow: false \}/);
  assert.doesNotMatch(page, /supabase-admin|createServerSupabase|SECRET/);
});

test("admin components only use the authenticated, capability-checked api schema", () => {
  const dir = new URL("components/admin/", root);
  const sources = readdirSync(dir).map(name => readFileSync(new URL(name, dir), "utf8")).join("\n");
  assert.doesNotMatch(sources, /supabase-admin|service_role|secretKey/);
  // The CSP only allows same-origin images: no signed storage URLs as <img>.
  assert.doesNotMatch(sources, /createSignedUrl/);
  assert.match(sources, /client\.schema\("api"\)\.rpc/);
  // Every mutation uses the same commands as the TeamZone app.
  for (const command of ["save_editorial_article", "transition_editorial_article", "configure_publication_v2", "request_team_publication",
    "decide_team_publication", "set_team_event_visibility_v2", "set_club_colors", "stage_club_badge", "set_club_badge", "save_public_partner"]) {
    assert.match(sources, new RegExp(`"${command}"`), command);
  }
});

test("the club and team pages link to the admin page only through the permission-checked entry", () => {
  const club = readFileSync(new URL("app/[clubSlug]/page.tsx", root), "utf8");
  const team = readFileSync(new URL("app/[clubSlug]/[teamSlug]/page.tsx", root), "utf8");
  assert.match(club, /<AdminEntry clubSlug=\{club\.slug\} \/>/);
  assert.match(team, /<AdminEntry clubSlug=\{club\.slug\} section="matcher" \/>/);
});
