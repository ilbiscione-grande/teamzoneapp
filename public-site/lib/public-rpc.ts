import type { SupabaseClient } from "@supabase/supabase-js";

export async function publicRpc(client: SupabaseClient, name: string, params: Record<string, unknown>) {
  const { data, error } = await client.schema("api").rpc(name, params);
  if (error) throw new Error(error.message);
  return data;
}
