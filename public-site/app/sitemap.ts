import type { MetadataRoute } from "next";
import { serverConfig } from "../lib/config";
import { publicRpc } from "../lib/public-rpc";
import { createServerSupabase } from "../lib/supabase-admin";

export const revalidate = 60;
type Entry = { path_url: string; external_path: string; canonical_hostname?: string; last_modified: string };

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  try {
    const config = serverConfig();
    const entries = await publicRpc(createServerSupabase(config), "public_sitemap_entries", {}) as Entry[];
    return entries.map((entry) => ({
      url: entry.canonical_hostname ? `https://${entry.canonical_hostname}${entry.external_path}` : `${config.publicOrigin}${entry.path_url}`,
      lastModified: new Date(entry.last_modified), changeFrequency: "daily", priority: entry.external_path === "/" ? 1 : 0.7,
    }));
  } catch { return []; }
}
