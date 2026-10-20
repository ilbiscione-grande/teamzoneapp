"use client";

import { createClient, type Session, type SupabaseClient } from "@supabase/supabase-js";
import { createContext, useCallback, useContext, useEffect, useState } from "react";
import type { Connection, LegalStatus } from "../lib/account";
import { requiresAcceptance } from "../lib/account";

type Links = { siteUrl: string; appUrl: string };

type Account = {
  /** The signed-in Supabase client for the apps' own API calls. */
  client: SupabaseClient | null;
  /** False until the configuration and any stored session are read. */
  ready: boolean;
  available: boolean;
  session: Session | null;
  legal: LegalStatus | null;
  /** True once the current terms are accepted: only then are apps opened. */
  accepted: boolean;
  displayName: string;
  connections: Connection[] | null;
  links: Links;
  error: string;
  signIn: (email: string, password: string) => Promise<string | null>;
  signUp: (email: string, password: string) => Promise<string | null>;
  signOut: () => Promise<void>;
  acceptLegal: () => Promise<string | null>;
};

const defaultLinks: Links = { siteUrl: "https://teamzoneapp.se", appUrl: "https://app.teamzoneapp.se" };
const Context = createContext<Account | null>(null);

export function AccountProvider({ children }: { children: React.ReactNode }) {
  const [client, setClient] = useState<SupabaseClient | null>(null);
  const [ready, setReady] = useState(false);
  const [available, setAvailable] = useState(false);
  const [session, setSession] = useState<Session | null>(null);
  const [legal, setLegal] = useState<LegalStatus | null>(null);
  const [displayName, setDisplayName] = useState("");
  const [connections, setConnections] = useState<Connection[] | null>(null);
  const [links, setLinks] = useState<Links>(defaultLinks);
  const [error, setError] = useState("");

  useEffect(() => {
    let disposed = false;
    let unsubscribe = () => {};
    fetch("/api/config", { cache: "no-store" }).then(async response => {
      const config = await response.json().catch(() => ({ available: false }));
      if (disposed) return;
      if (!config.available) { setReady(true); return; }
      setLinks({ siteUrl: config.siteUrl, appUrl: config.appUrl });
      const authClient = createClient(config.url, config.publishableKey, {
        // Its own storage key: the session is Webtools' own sign-in.
        auth: { storageKey: "teamzone-webtools", detectSessionInUrl: true, flowType: "pkce" },
        global: { fetch: (input, init) => fetch(input, { ...init, cache: "no-store" }) },
      });
      setAvailable(true);
      setClient(authClient);
      const { data } = authClient.auth.onAuthStateChange((_event, next) => {
        if (disposed) return;
        setSession(next);
        if (!next) { setLegal(null); setConnections(null); setDisplayName(""); }
        setReady(true);
      });
      unsubscribe = () => data.subscription.unsubscribe();
    }).catch(() => {
      if (!disposed) { setError("Kontotjänsten kunde inte nås. Ladda om sidan och försök igen."); setReady(true); }
    });
    return () => { disposed = true; unsubscribe(); };
  }, []);

  // The account's terms first; name and connections once they are accepted.
  const loadAccount = useCallback(async (authClient: SupabaseClient) => {
    const api = authClient.schema("api");
    const status = await api.rpc("get_legal_status");
    if (status.error || !status.data) { setError("Kontot kunde inte läsas. Försök igen."); return; }
    const value = status.data as LegalStatus;
    setLegal(value);
    if (requiresAcceptance(value)) return;
    const [profile, contexts] = await Promise.all([api.rpc("get_profile"), api.rpc("get_my_contexts")]);
    const row = Array.isArray(profile.data) ? profile.data[0] : profile.data;
    setDisplayName(typeof row?.display_name === "string" ? row.display_name.trim() : "");
    setConnections(contexts.error ? [] : (contexts.data as Connection[]) ?? []);
  }, []);

  useEffect(() => {
    if (!client || !session) return;
    setError("");
    loadAccount(client).catch(() => setError("Kontot kunde inte läsas. Försök igen."));
  }, [client, session, loadAccount]);

  const signIn = useCallback(async (email: string, password: string) => {
    if (!client) return "Kontotjänsten är inte tillgänglig just nu.";
    const { error: signInError } = await client.auth.signInWithPassword({ email: email.trim(), password });
    if (!signInError) return null;
    return signInError.message.toLowerCase().includes("not confirmed")
      ? "Bekräfta din e-postadress via länken i mejlet först."
      : "Fel e-post eller lösenord.";
  }, [client]);

  const signUp = useCallback(async (email: string, password: string) => {
    if (!client) return "Kontotjänsten är inte tillgänglig just nu.";
    const { error: signUpError } = await client.auth.signUp({
      email: email.trim(),
      password,
      options: { emailRedirectTo: `${window.location.origin}/logga-in?konto=bekraftat` },
    });
    return signUpError ? "Kontot kunde inte skapas. Kontrollera adressen eller logga in om du redan har ett konto." : null;
  }, [client]);

  const signOut = useCallback(async () => { await client?.auth.signOut({ scope: "local" }); }, [client]);

  const acceptLegal = useCallback(async () => {
    if (!client || !legal) return "Villkoren kunde inte läsas.";
    const { error: acceptError } = await client.schema("api").rpc("accept_current_legal", {
      terms_version: legal.terms_version,
      privacy_version: legal.privacy_version,
      marketing_opt_in: false,
      idempotency_key: crypto.randomUUID(),
    });
    if (acceptError) return "Godkännandet kunde inte sparas. Försök igen.";
    await loadAccount(client);
    return null;
  }, [client, legal, loadAccount]);

  const accepted = !!legal && !requiresAcceptance(legal);
  return (
    <Context.Provider value={{ client, ready, available, session, legal, accepted, displayName, connections, links, error, signIn, signUp, signOut, acceptLegal }}>
      {children}
    </Context.Provider>
  );
}

export function useAccount(): Account {
  const account = useContext(Context);
  if (!account) throw new Error("AccountProvider missing");
  return account;
}
