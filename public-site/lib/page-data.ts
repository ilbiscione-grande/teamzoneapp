import { headers } from "next/headers";
import { cache } from "react";
import { serverConfig } from "./config";
import { hmacHex, resolveClientIp } from "./request-security";
import { createServerSupabase } from "./supabase-admin";
import { publicRpc } from "./public-rpc";

async function context() {
  const config = serverConfig();
  const requestHeaders = await headers();
  const rawIp = resolveClientIp(requestHeaders.get("x-forwarded-for"), config.trustedProxyHops);
  return { client: createServerSupabase(config), ipHash: hmacHex(config.ipHmacSecret, rawIp) };
}

export async function canonicalUrl(defaultPath: string) {
  const requestHeaders = await headers();
  const origin = requestHeaders.get("x-teamzone-canonical-origin");
  const originalPath = requestHeaders.get("x-teamzone-original-path");
  if (!origin || !originalPath || !originalPath.startsWith("/") || /[?#]/.test(originalPath)) return defaultPath;
  try {
    const url = new URL(origin);
    if (url.protocol !== "https:" || url.pathname !== "/") return defaultPath;
    return `${url.origin}${originalPath}`;
  } catch { return defaultPath; }
}

export const getClubPage = cache(async (slug: string) => {
  const { client, ipHash } = await context();
  return publicRpc(client, "public_get_club", { slug, ip_hash: ipHash });
});

export const getTeamPage = cache(async (clubSlug: string, teamSlug: string) => {
  const { client, ipHash } = await context();
  return publicRpc(client, "public_get_team", { club_slug: clubSlug, team_slug: teamSlug, ip_hash: ipHash });
});

export const getPublications = cache(async (clubId: string, teamId?: string) => {
  const { client, ipHash } = await context();
  return publicRpc(client, "public_list_publications", {
    club_id: clubId, team_id: teamId ?? null, before_published_at: null,
    before_id: null, ip_hash: ipHash, page_limit: 6,
  });
});

export const getTeamEvents = cache(async (teamId: string) => {
  const { client, ipHash } = await context();
  return publicRpc(client, "public_list_team_events", {
    team_id: teamId, before_starts_at: null, before_id: null,
    ip_hash: ipHash, page_limit: 8,
  });
});

export const getClubEvents = cache(async (clubId: string) => {
  const { client, ipHash } = await context();
  return publicRpc(client, "public_list_club_events", {
    club_id: clubId, ip_hash: ipHash, page_limit: 12,
  });
});

export const getPublicArticle = cache(async (clubSlug: string, articleSlug: string) => {
  const { client, ipHash } = await context();
  return publicRpc(client, "public_get_article", {
    club_slug: clubSlug, article_slug: articleSlug, ip_hash: ipHash,
  });
});
