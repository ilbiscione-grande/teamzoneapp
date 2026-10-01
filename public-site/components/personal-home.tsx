"use client";

import Link from "next/link";
import { useState } from "react";
import { safeReturnPath } from "../lib/personal-home";

import { usePersonalAccount } from "./personal-account";
import { PersonalDashboard } from "./personal-dashboard";
import { TeamNotifications } from "./team-notifications";
import { PortalHero } from "./portal";

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

  const showLogin = ready && enabled && !session;
  const login = showLogin ? <form onSubmit={signIn} className="pz-login" aria-labelledby="login-title">
    <p className="cs-kicker">Samma konto överallt</p>
    <h2 id="login-title">Logga in</h2>
    <label className="field" htmlFor="account-email">E-post<input id="account-email" type="email" autoComplete="username" required maxLength={320} value={email} onChange={e => setEmail(e.target.value)} disabled={busy} /></label>
    <label className="field" htmlFor="account-password">Lösenord<input id="account-password" type="password" autoComplete="current-password" required maxLength={1024} value={password} onChange={e => setPassword(e.target.value)} disabled={busy} /></label>
    {authError && <p role="alert" className="pz-error">{authError}</p>}
    <button className="primary-button" disabled={busy}>{busy ? "Loggar in…" : "Logga in"}</button>
    <p className="pz-small"><a href="https://app.teamzoneapp.se">Skapa konto eller återställ lösenord i TeamZone</a></p>
  </form> : undefined;

  return <>
    <PortalHero kicker={session ? `Inloggad · ${session.user.email ?? ""}` : "Din hemmaplan"} title={session ? "Min startsida" : "Nära lagen du följer"} aside={login}>
      <p className="pz-lead">Dina lag, senaste nyheterna, matchresultaten och kalendern. Samlat på ett ställe.</p>
      <div className="cs-hero-actions">
        <Link className="cs-button" href="/klubbar">Sök klubbar och lag</Link>
        {session && <button className="cs-button ghost" disabled={busy} onClick={signOut}>Logga ut</button>}
      </div>
      {!session && <p className="pz-note">Publika klubb- och lagsidor kan du läsa utan att logga in.</p>}
    </PortalHero>

    {(!ready || error || (authError && session)) && <div className="cs-wrap pz-status">
      {!ready && <p role="status">Hämtar ditt konto…</p>}
      {error && <p role="alert">{error} {session && <button className="cs-button small" onClick={refresh}>Försök igen</button>}</p>}
      {authError && session && <p role="alert">{authError}</p>}
    </div>}

    {ready && !enabled && !error && <section className="cs-section"><div className="cs-wrap"><div className="cs-empty"><strong>Din personliga startsida är på väg.</strong> Under tiden kan du söka fram klubbar och lag och läsa deras publika sidor.</div></div></section>}

    {ready && !session && <section className="cs-section alt">
      <div className="cs-wrap">
        <div className="cs-section-head"><div><p className="cs-kicker">Logga in och följ dina favoriter</p><h2>Allt om dina lag</h2></div></div>
        <div className="pz-features">
          <article><span aria-hidden="true">01</span><h3>Följ lag och klubbar</h3><p>Följ lag och klubbar så visas dina genvägar, nyheter och publicerade slutresultat här, även när du byter enhet.</p></article>
          <article><span aria-hidden="true">02</span><h3>Matcher och resultat</h3><p>Se kommande matcher, slutresultat och matchrapporter från lagen du är med i eller håller koll på.</p></article>
          <article><span aria-hidden="true">03</span><h3>Privat för dig</h3><p>Dina följda lag och klubbar är privata för ditt konto. Klubbarnas publika sidor kan alla läsa.</p></article>
        </div>
      </div>
    </section>}

    {session && <section className="cs-section alt pz-dashboard">
      <div className="cs-wrap">
        <TeamNotifications key={`notifications:${session.user.id}`} />
        <PersonalDashboard key={session.user.id} />
      </div>
    </section>}
  </>;

}

