"use client";

import { createClient, type Session, type SupabaseClient } from "@supabase/supabase-js";
import { createContext, useCallback, useContext, useEffect, useRef, useState } from "react";
import type { Cursor, PersonalHome } from "../lib/personal-home";
import { mergeFeed } from "../lib/personal-home";

type Account = { client: SupabaseClient | null; session: Session | null; ready: boolean; enabled: boolean; home: PersonalHome | null; loading: boolean; error: string; refresh: () => void; more: () => void };
const Context = createContext<Account | null>(null);

export function PersonalAccount({ children }: { children: React.ReactNode }) {
  const [client, setClient] = useState<SupabaseClient | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [ready, setReady] = useState(false);
  const [enabled, setEnabled] = useState(false);
  const [home, setHome] = useState<PersonalHome | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [cursor, setCursor] = useState<Cursor | null>(null);
  const [revision, setRevision] = useState(0);
  const epoch = useRef(0);
  useEffect(() => {
    let disposed = false;
    let unsubscribe = () => {};
    fetch("/api/public/v1/account-config", { cache: "no-store" }).then(async response => {
      if (!response.ok) throw new Error("config_unavailable");
      const config = await response.json();
      if (disposed) return;
      if (!config.available) { setReady(true); return; }
      const authClient = createClient(config.url, config.publishableKey, {
        auth: { storageKey: "teamzone-public-account", detectSessionInUrl: false },
        global: { fetch: (input, init) => fetch(input, { ...init, cache: "no-store" }) },
      });
      setEnabled(true);
      setClient(authClient);
      const { data } = authClient.auth.onAuthStateChange((_event, next) => {
        if (disposed) return;
        epoch.current++;
        setHome(null);
        setError("");
        setCursor(null);
        setSession(next);
        setReady(true);
      });
      unsubscribe = () => data.subscription.unsubscribe();
    }).catch(() => { if (!disposed) { setError("Kontotjänsten kunde inte nås. Försök ladda om sidan."); setReady(true); } });
    return () => { disposed = true; unsubscribe(); };
  }, []);
  useEffect(() => {
    if (!client || !session) return;
    let disposed = false;
    const version = epoch.current;
    setLoading(true);
    setError("");
    Promise.resolve(client.schema("api").rpc("get_personal_public_home", cursor ?? {})).then(({ data, error: rpcError }) => {
      if (disposed || version !== epoch.current) return;
      if (rpcError) { setError("Din startsida kunde inte hämtas. Försök igen."); return; }
      const next = data as PersonalHome;
      setHome(previous => cursor && previous ? { ...next, items: mergeFeed(previous.items, next.items) } : next);
    }).catch(() => { if (!disposed && version === epoch.current) setError("Din startsida kunde inte hämtas. Försök igen."); })
      .finally(() => { if (!disposed && version === epoch.current) setLoading(false); });
    return () => { disposed = true; };
  }, [client, session, cursor, revision]);
  const refresh = useCallback(() => { epoch.current++; setCursor(null); setHome(null); setRevision(v => v + 1); }, []);
  return <Context.Provider value={{ client, session, ready, enabled, home, loading, error, refresh, more: () => { if (!loading && home?.next_cursor) setCursor(home.next_cursor); } }}>{children}</Context.Provider>;
}

export function usePersonalAccount() {
  const account = useContext(Context);
  if (!account) throw new Error("PersonalAccount provider missing");
  return account;
}
