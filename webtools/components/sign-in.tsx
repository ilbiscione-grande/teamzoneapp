"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { useEffect, useState } from "react";
import { passwordRule, validCredentials } from "../lib/account";
import { safeReturnTo } from "../lib/apps";
import { useAccount } from "./account";
import { ForgotPassword, NewPasswordForm } from "./password";

export function SignIn() {
  const { ready, available, session, signIn, signUp } = useAccount();
  const params = useSearchParams();
  const router = useRouter();
  const returnTo = safeReturnTo(params.get("returnTo"));
  const confirmed = params.get("konto") === "bekraftat";
  // Come from the mail's link for a new password: signed in by it, the password is chosen here.
  const recovering = params.get("losenord") === "nytt";
  const [mode, setMode] = useState<"in" | "up" | "forgot">(params.get("skapa") === "1" ? "up" : "in");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [sent, setSent] = useState(false);

  // Signed in (also straight from the confirmation link): on to the page.
  useEffect(() => { if (session && !recovering) router.replace(returnTo); }, [session, recovering, returnTo, router]);

  if (!ready) return <p className="wt-status">Laddar…</p>;
  if (!available) return <p className="wt-status" role="alert">Inloggningen är inte tillgänglig just nu. Försök igen senare.</p>;
  if (recovering && session) {
    return (
      <section className="wt-panel wt-signin" aria-labelledby="signin-title">
        <h1 id="signin-title">Välj ett nytt lösenord</h1>
        <NewPasswordForm submitLabel="Spara lösenordet" onDone={() => router.replace(returnTo)} />
      </section>
    );
  }
  if (session) return <p className="wt-status">Du är inloggad. Skickar dig vidare…</p>;
  if (mode === "forgot" || recovering) {
    return (
      <section className="wt-panel wt-signin" aria-labelledby="signin-title">
        {recovering && <p className="wt-note" role="alert">Länken gäller inte längre. Be om en ny här.</p>}
        <ForgotPassword initialEmail={email} onBack={() => { setMode("in"); setError(""); if (recovering) router.replace("/logga-in"); }} />
      </section>
    );
  }

  const submit = async (event: React.FormEvent) => {
    event.preventDefault();
    const invalid = validCredentials(email, password, mode === "up");
    if (invalid) { setError(invalid); return; }
    setBusy(true);
    setError("");
    const failure = mode === "in" ? await signIn(email, password) : await signUp(email, password);
    setBusy(false);
    if (failure) { setError(failure); return; }
    if (mode === "up") setSent(true);
  };

  return (
    <section className="wt-panel wt-signin" aria-labelledby="signin-title">
      <div className="wt-tabs" role="tablist" aria-label="Logga in eller skapa konto">
        <button type="button" role="tab" aria-selected={mode === "in"} onClick={() => { setMode("in"); setError(""); setSent(false); }}>Logga in</button>
        <button type="button" role="tab" aria-selected={mode === "up"} onClick={() => { setMode("up"); setError(""); }}>Skapa konto</button>
      </div>
      <h1 id="signin-title">{mode === "in" ? "Logga in med ditt TeamZone-konto" : "Skapa ett TeamZone-konto"}</h1>
      {confirmed && mode === "in" && <p className="wt-note">Din e-postadress är bekräftad. Logga in för att fortsätta.</p>}
      {sent ? (
        <p className="wt-note" role="status">
          Vi har skickat ett mejl till <strong>{email.trim()}</strong>. Klicka på länken i mejlet för att bekräfta adressen, så kommer du tillbaka hit.
        </p>
      ) : (
        <form onSubmit={submit} className="wt-form" noValidate>
          <label>E-post<input type="email" autoComplete="email" value={email} onChange={event => setEmail(event.target.value)} required /></label>
          <label>Lösenord<input type="password" autoComplete={mode === "in" ? "current-password" : "new-password"} value={password} onChange={event => setPassword(event.target.value)} required minLength={mode === "up" ? 8 : undefined} /></label>
          {mode === "up" && <p className="wt-small">{passwordRule}</p>}
          {mode === "up" && <p className="wt-small">Kontot är ett vanligt TeamZone-konto och fungerar även i appen. Du behöver inte vara med i något lag.</p>}
          {error && <p role="alert" className="wt-error">{error}</p>}
          <button type="submit" className="wt-button" disabled={busy}>{mode === "in" ? "Logga in" : "Skapa konto"}</button>
          {mode === "in" && <p className="wt-small"><button type="button" className="wt-link-button" onClick={() => { setMode("forgot"); setError(""); }}>Glömt lösenordet?</button></p>}
        </form>
      )}
    </section>
  );
}
