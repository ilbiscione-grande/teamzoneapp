"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { safeReturnPath } from "../lib/personal-home";

import { usePersonalAccount } from "./personal-account";
import { PersonalDashboard } from "./personal-dashboard";
import { TeamNotifications } from "./team-notifications";
import { PortalHero } from "./portal";
import { useTurnstile } from "./turnstile";

export function PersonalHomePage() {
  const { client, session, ready, enabled, error, refresh } = usePersonalAccount();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [authError, setAuthError] = useState("");
  const [mode, setMode] = useState<"login" | "signup">("login");
  const [notice, setNotice] = useState("");
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    if (params.get("konto") === "bekraftat") setNotice("Din e-postadress är bekräftad. Logga in för att börja följa lag och klubbar.");
    else if (params.get("konto") === "skapa") setMode("signup");
  }, []);

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
  const login = showLogin ? <div className="pz-login">
    <div className="pz-tabs" role="tablist" aria-label="Konto">
      <button type="button" role="tab" aria-selected={mode === "login"} onClick={() => { setMode("login"); setAuthError(""); }}>Logga in</button>
      <button type="button" role="tab" aria-selected={mode === "signup"} onClick={() => { setMode("signup"); setAuthError(""); }}>Skapa konto</button>
    </div>
    {mode === "login" ? <form onSubmit={signIn} className="pz-login-form" aria-labelledby="login-title">
      <p className="cs-kicker">Samma konto överallt</p>
      <h2 id="login-title">Logga in</h2>
      {notice && <p role="status" className="pz-success">{notice}</p>}
      <label className="field" htmlFor="account-email">E-post<input id="account-email" type="email" autoComplete="username" required maxLength={320} value={email} onChange={e => setEmail(e.target.value)} disabled={busy} /></label>
      <label className="field" htmlFor="account-password">Lösenord<input id="account-password" type="password" autoComplete="current-password" required maxLength={1024} value={password} onChange={e => setPassword(e.target.value)} disabled={busy} /></label>
      {authError && <p role="alert" className="pz-error">{authError}</p>}
      <button className="primary-button" disabled={busy}>{busy ? "Loggar in…" : "Logga in"}</button>
      <p className="pz-small">Inget konto? <button type="button" className="pz-link" onClick={() => setMode("signup")}>Skapa ett följarkonto</button> · <a href="https://app.teamzoneapp.se">Glömt lösenordet?</a></p>
    </form> : <SignUpForm onDone={(address) => { setEmail(address); setMode("login"); setNotice(`Vi har skickat ett mejl till ${address}. Klicka på länken i mejlet för att bekräfta kontot och logga sedan in här.`); }} />}
  </div> : undefined;


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

/** A follower account: for following public club and team pages only. */
function SignUpForm({ onDone }: { onDone: (email: string) => void }) {
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [acceptLegal, setAcceptLegal] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const captcha = useTurnstile("signup");

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (busy) return;
    if (password.length < 8) { setError("Lösenordet behöver vara minst 8 tecken."); return; }
    if (!acceptLegal) { setError("Du behöver godkänna användarvillkoren och integritetspolicyn."); return; }
    if (!captcha.token) { setError("Vänta tills bot-skyddet är klart och försök igen."); return; }
    setBusy(true); setError("");
    try {
      const response = await fetch("/api/public/v1/account/sign-up", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: email.trim(), password, displayName: name.trim(), acceptLegal, captchaToken: captcha.token }),
      });
      if (!response.ok) {
        const data = await response.json().catch(() => ({})) as { error?: string };
        throw new Error(data.error || "Kontot kunde inte skapas. Försök igen.");
      }
      setPassword("");
      onDone(email.trim());
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Kontot kunde inte skapas. Försök igen.");
    } finally {
      setBusy(false);
      captcha.reset();
    }
  }

  return <form onSubmit={submit} className="pz-login-form" aria-labelledby="signup-title">
    <p className="cs-kicker">Följarkonto</p>
    <h2 id="signup-title">Skapa konto</h2>
    <p className="pz-small muted">För dig som vill följa lag och klubbar. Kontot hör inte till något lag. Är du spelare, ledare eller vårdnadshavare kan du senare gå med i ditt lag via appen med samma konto.</p>
    <label className="field" htmlFor="signup-name">Namn<input id="signup-name" autoComplete="name" required maxLength={80} value={name} onChange={e => setName(e.target.value)} disabled={busy} /></label>
    <label className="field" htmlFor="signup-email">E-post<input id="signup-email" type="email" autoComplete="email" required maxLength={320} value={email} onChange={e => setEmail(e.target.value)} disabled={busy} /></label>
    <label className="field" htmlFor="signup-password">Lösenord<input id="signup-password" type="password" autoComplete="new-password" required minLength={8} maxLength={128} value={password} onChange={e => setPassword(e.target.value)} disabled={busy} /></label>
    <label className="pz-check"><input type="checkbox" checked={acceptLegal} onChange={e => setAcceptLegal(e.target.checked)} disabled={busy} /><span>Jag godkänner <Link href="/villkor" target="_blank">användarvillkoren</Link> och har läst <Link href="/integritet" target="_blank">integritetspolicyn</Link>.</span></label>
    {captcha.slot}
    {error && <p role="alert" className="pz-error">{error}</p>}
    <button className="primary-button" disabled={busy}>{busy ? "Skapar konto…" : "Skapa konto"}</button>
  </form>;
}
