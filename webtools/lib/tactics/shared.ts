// A shared Tacticsboard link, read on Webtools' server with the secret key:
// the database lets only the server read it.
import { createClient } from "@supabase/supabase-js";
import type { Board, ProjectKind } from "./model.ts";

export type SharedTactics = {
  name: string;
  kind: ProjectKind;
  updated_at: string;
  team_name: string | null;
  /** The one board the link is for, or null for the whole project. */
  board_id: string | null;
  boards: Board[];
};

export async function loadSharedTactics(token: string): Promise<SharedTactics | null> {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SECRET_KEY;
  if (!url || !key || !/^[0-9a-f]{40}$/.test(token)) return null;
  const client = createClient(url, key, {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
    global: { headers: { "X-Client-Info": "teamzone-webtools-server/0.1" } },
  });
  const { data, error } = await client.schema("api").rpc("get_shared_tactics", { target_token: token });
  if (error) {
    console.error("shared tactics", error.message);
    return null;
  }
  const shared = data as SharedTactics | null;
  return shared && Array.isArray(shared.boards) && shared.boards.length > 0 ? shared : null;
}
