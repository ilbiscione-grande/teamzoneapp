"use client";

import Link from "next/link";
import { useState } from "react";
import { safeReturnPath } from "../lib/personal-home";

import { usePersonalAccount } from "./personal-account";
import { PersonalDashboard } from "./personal-dashboard";
import { TeamNotifications } from "./team-notifications";

export function PersonalHomePage() {
  const { client, session, ready, enabled, error, refresh } = usePersonalAccount();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [authError, setAuthError] = useState("");

  async function signIn(event: React.FormEvent) {
    event.preventDefault();
    if (!client || busy) return;
    setBusy(true); setAuthError("");
    try {
      // Reuse the application's existing monitored password entry point.
      const { data, error: signInError } = await client.functions.invoke("auth-password-sign-in", { body: { email: email.trim(), password } });
      if (signInError || !data?.refresh_token) throw new Error("sign_in_failed");
      const { error: sessionError } = await client.auth.refreshSession({ refresh_token: data.refresh_token });
      if (sessionError) throw sessionError;
      setPassword("");
      const path = safeReturnPath(new URLSearchParams(window.location.search).get("returnTo"));
      if (path) window.location.assign(path);
    } catch { setAuthError("Det gick inte att logga in. Kontrollera e-post och lösenord och försök igen."); }
    finally { setBusy(false); }
  }
  async function signOut() {
    if (!client || busy) return;
    setBusy(true); setAuthError("");
    try { const { error } = await client.auth.signOut({ scope: "local" }); if (error) throw error; }
    catch { setAuthError("Utloggningen kunde inte slutföras. Försök igen."); }
    finally { setBusy(false); }
  }

  return <>
    <section className={`hero-card personal-hero ${session ? "dashboard-hero" : ""}`}>
      <p className="eyebrow">Din hemmaplan</p><h1>{session ? "Min startsida" : "Nära lagen du följer"}</h1>
      <p className="lead">Dina lag, senaste nyheterna, matchresultaten och kalendern. Samlat på ett ställe.</p>
      {!session && <p>Publika klubb- och lagsidor kan du läsa utan att logga in.</p>}
      <Link className="follow-button" href="/klubbar">Sök klubbar och lag →</Link>
    </section>
    {!ready && <p role="status">Hämtar ditt konto…</p>}
    {error && <p role="alert">{error} {session && <button onClick={refresh}>Försök igen</button>}</p>}
    {authError && <p role="alert">{authError}</p>}
    {ready && !enabled && !error && <section className="panel home-section"><h2>Din personliga startsida är på väg</h2><p>Under tiden kan du söka fram klubbar och lag och läsa deras publika sidor.</p></section>}
    {ready && enabled && !session && <section className="panel home-section account-panel">
      <div><p className="eyebrow">Samma konto överallt</p><h2>Logga in och följ dina favoriter</h2><p>Följ lag och klubbar så visas dina genvägar, nyheter och publicerade slutresultat här, även när du byter enhet.</p><p>Dina följda lag och klubbar är privata för ditt konto.</p><p><a href="https://app.teamzoneapp.se">Skapa konto eller återställ lösenord i TeamZone</a></p></div>
      <form onSubmit={signIn} className="account-form">
        <label htmlFor="account-email">E-post</label><input id="account-email" type="email" autoComplete="username" required maxLength={320} value={email} onChange={e => setEmail(e.target.value)} disabled={busy} />
        <label htmlFor="account-password">Lösenord</label><input id="account-password" type="password" autoComplete="current-password" required maxLength={1024} value={password} onChange={e => setPassword(e.target.value)} disabled={busy} />
        <button className="primary-button" disabled={busy}>{busy ? "Loggar in…" : "Logga in"}</button>
      </form>
    </section>}
    {session && <>
      <div className="account-bar"><span>Inloggad som {session.user.email}</span><button disabled={busy} onClick={signOut}>Logga ut</button></div>
      <TeamNotifications key={`notifications:${session.user.id}`} />
      <PersonalDashboard key={session.user.id} />
    </>}
  </>;
}

