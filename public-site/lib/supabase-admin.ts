import { createClient } from "@supabase/supabase-js";
import type { ServerConfig } from "./config";

export function createServerSupabase(config: ServerConfig) {
  return createClient(config.supabaseUrl, config.supabaseSecretKey, {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
    global: { headers: { "X-Client-Info": "teamzone-public-server/0.1" } },
  });
}
