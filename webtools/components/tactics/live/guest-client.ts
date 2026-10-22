"use client";

// A guest's own Supabase client for live lessons: an anonymous sign-in kept
// apart from Webtools' account (its own storage), so following a lesson
// never signs anyone in to Webtools itself.
import { createClient, type SupabaseClient } from "@supabase/supabase-js";

let guest: Promise<SupabaseClient> | null = null;

export function guestClient(): Promise<SupabaseClient> {
  guest ??= fetch("/api/config", { cache: "no-store" })
    .then(response => response.json())
    .then((config: { available: boolean; url: string; publishableKey: string }) => {
      if (!config.available) throw new Error("unavailable");
      return createClient(config.url, config.publishableKey, {
        auth: { storageKey: "teamzone-live-guest", detectSessionInUrl: false, persistSession: true },
      });
    });
  guest.catch(() => { guest = null; });
  return guest;
}

/** The guest's client, signed in anonymously; null with why when guests cannot come in. */
export async function signedInGuest(): Promise<{ client: SupabaseClient } | { error: string }> {
  try {
    const client = await guestClient();
    const { data } = await client.auth.getSession();
    if (data.session) return { client };
    const { error } = await client.auth.signInAnonymously();
    if (error) return { error: "Gäster kan inte gå med just nu. Logga in för att vara med." };
    return { client };
  } catch {
    return { error: "Det gick inte att ansluta. Ladda om sidan och försök igen." };
  }
}
