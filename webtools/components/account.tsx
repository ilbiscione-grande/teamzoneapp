"use client";

import { createClient, type Session, type SupabaseClient } from "@supabase/supabase-js";
import { createContext, useCallback, useContext, useEffect, useState } from "react";
import type { Connection, LegalStatus } from "../lib/account";
import { requiresAcceptance } from "../lib/account";
import { useT } from "./language";

type Links = { siteUrl: string; appUrl: string | null; tacticsboardOnly: boolean };

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
  /** Mails a link that signs in and opens the page for a new password. */
  requestPasswordReset: (email: string) => Promise<string | null>;
  updatePassword: (password: string) => Promise<string | null>;
};

const defaultLinks: Links = { siteUrl: "https://teamzoneapp.se", appUrl: null, tacticsboardOnly: true };
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
  const t = useT();

  useEffect(() => {
    let disposed = false;
    let unsubscribe = () => {};
    fetch("/api/config", { cache: "no-store" }).then(async response => {
      const config = await response.json().catch(() => ({ available: false }));
      if (disposed) return;
      if (!config.available) { setReady(true); return; }
      setLinks({ siteUrl: config.siteUrl, appUrl: config.appUrl, tacticsboardOnly: config.tacticsboardOnly === true });
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
      if (!disposed) { setError(t("Kontotjänsten kunde inte nås. Ladda om sidan och försök igen.")); setReady(true); }
    });
    return () => { disposed = true; unsubscribe(); };
  }, [t]);

  // The account's terms first; name and connections once they are accepted.
  const loadAccount = useCallback(async (authClient: SupabaseClient) => {
    const api = authClient.schema("api");
    const status = await api.rpc("get_legal_status");
    if (status.error || !status.data) { setError(t("Kontot kunde inte läsas. Försök igen.")); return; }
    const value = status.data as LegalStatus;
    setLegal(value);
    if (requiresAcceptance(value)) return;
    const [profile, contexts] = await Promise.all([api.rpc("get_profile"), api.rpc("get_my_contexts")]);
    const row = Array.isArray(profile.data) ? profile.data[0] : profile.data;
    setDisplayName(typeof row?.display_name === "string" ? row.display_name.trim() : "");
    setConnections(contexts.error ? [] : (contexts.data as Connection[]) ?? []);
  }, [t]);

  useEffect(() => {
    if (!client || !session) return;
    setError("");
    loadAccount(client).catch(() => setError(t("Kontot kunde inte läsas. Försök igen.")));
  }, [client, session, loadAccount, t]);

  const signIn = useCallback(async (email: string, password: string) => {
    if (!client) return t("Kontotjänsten är inte tillgänglig just nu.");
    const { error: signInError } = await client.auth.signInWithPassword({ email: email.trim(), password });
    if (!signInError) return null;
    return signInError.message.toLowerCase().includes("not confirmed")
      ? t("Bekräfta din e-postadress via länken i mejlet först.")
      : t("Fel e-post eller lösenord.");
  }, [client, t]);

  const signUp = useCallback(async (email: string, password: string) => {
    if (!client) return t("Kontotjänsten är inte tillgänglig just nu.");
    const { error: signUpError } = await client.auth.signUp({
      email: email.trim(),
      password,
      options: { emailRedirectTo: `${window.location.origin}/logga-in?konto=bekraftat` },
    });
    return signUpError ? "Kontot kunde inte skapas. Kontrollera adressen eller logga in om du redan har ett konto." : null;
  }, [client, t]);

  const signOut = useCallback(async () => { await client?.auth.signOut({ scope: "local" }); }, [client]);

  // The same answer whether the address has an account or not.
  const requestPasswordReset = useCallback(async (email: string) => {
    if (!client) return t("Kontotjänsten är inte tillgänglig just nu.");
    const { error: resetError } = await client.auth.resetPasswordForEmail(email.trim(), {
      redirectTo: `${window.location.origin}/logga-in?losenord=nytt`,
    });
    return resetError && resetError.status === 429 ? t("För många försök. Vänta en stund och försök igen.") : null;
  }, [client, t]);

  const updatePassword = useCallback(async (password: string) => {
    if (!client) return t("Kontotjänsten är inte tillgänglig just nu.");
    const { error: updateError } = await client.auth.updateUser({ password });
    if (!updateError) return null;
    if (updateError.code === "same_password") return t("Välj ett annat lösenord än det du har nu.");
    if (updateError.code === "weak_password") return t("Lösenordet är för svagt eller har läckt tidigare. Välj ett annat.");
    return t("Lösenordet kunde inte sparas. Försök igen.");
  }, [client, t]);

  const acceptLegal = useCallback(async () => {
    if (!client || !legal) return t("Villkoren kunde inte läsas.");
    const { error: acceptError } = await client.schema("api").rpc("accept_current_legal", {
      terms_version: legal.terms_version,
      privacy_version: legal.privacy_version,
      marketing_opt_in: false,
      idempotency_key: crypto.randomUUID(),
    });
    if (acceptError) return t("Godkännandet kunde inte sparas. Försök igen.");
    await loadAccount(client);
    return null;
  }, [client, legal, loadAccount, t]);

  const accepted = !!legal && !requiresAcceptance(legal);
  return (
    <Context.Provider value={{ client, ready, available, session, legal, accepted, displayName, connections, links, error, signIn, signUp, signOut, acceptLegal, requestPasswordReset, updatePassword }}>
      {children}
    </Context.Provider>
  );
}

export function useAccount(): Account {
  const account = useContext(Context);
  if (!account) throw new Error("AccountProvider missing");
  return account;
}
