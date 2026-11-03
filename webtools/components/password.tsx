"use client";

// A forgotten password: the address gets a link that signs in and opens the
// sign-in page in its "new password" step. The same step changes the
// password on the account page.
import { useState } from "react";
import { passwordRule, validCredentials, validNewPassword } from "../lib/account";
import { useAccount } from "./account";

export function ForgotPassword({ initialEmail, onBack }: { initialEmail: string; onBack: () => void }) {
  const { requestPasswordReset } = useAccount();
  const [email, setEmail] = useState(initialEmail);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [sent, setSent] = useState(false);

  const submit = async (event: React.FormEvent) => {
    event.preventDefault();
    // Only the address is checked here; any password passes.
    const invalid = validCredentials(email, "x", false);
    if (invalid) { setError(invalid); return; }
    setBusy(true);
    setError("");
    const failure = await requestPasswordReset(email);
    setBusy(false);
    if (failure) setError(failure); else setSent(true);
  };

  return (
    <>
      <h1 id="signin-title">Glömt lösenordet</h1>
      {sent ? (
        <p className="wt-note" role="status">
          Om det finns ett konto för <strong>{email.trim()}</strong> har vi skickat ett mejl med en länk. Klicka på den för att välja ett nytt lösenord.
        </p>
      ) : (
        <form onSubmit={submit} className="wt-form" noValidate>
          <p className="wt-small">Skriv din e-postadress så skickar vi en länk där du väljer ett nytt lösenord.</p>
          <label>E-post<input type="email" autoComplete="email" value={email} onChange={event => setEmail(event.target.value)} required /></label>
          {error && <p role="alert" className="wt-error">{error}</p>}
          <button type="submit" className="wt-button" disabled={busy}>Skicka länken</button>
        </form>
      )}
      <p className="wt-small"><button type="button" className="wt-link-button" onClick={onBack}>Tillbaka till inloggningen</button></p>
    </>
  );
}

/** The new password, written twice. */
export function NewPasswordForm({ submitLabel, onDone }: { submitLabel: string; onDone: () => void }) {
  const { updatePassword } = useAccount();
  const [password, setPassword] = useState("");
  const [repeated, setRepeated] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  const submit = async (event: React.FormEvent) => {
    event.preventDefault();
    const invalid = validNewPassword(password, repeated);
    if (invalid) { setError(invalid); return; }
    setBusy(true);
    setError("");
    const failure = await updatePassword(password);
    setBusy(false);
    if (failure) { setError(failure); return; }
    setPassword("");
    setRepeated("");
    onDone();
  };

  return (
    <form onSubmit={submit} className="wt-form" noValidate>
      <label>Nytt lösenord<input type="password" autoComplete="new-password" value={password} onChange={event => setPassword(event.target.value)} required minLength={8} /></label>
      <label>Upprepa lösenordet<input type="password" autoComplete="new-password" value={repeated} onChange={event => setRepeated(event.target.value)} required minLength={8} /></label>
      <p className="wt-small">{passwordRule}</p>
      {error && <p role="alert" className="wt-error">{error}</p>}
      <button type="submit" className="wt-button" disabled={busy}>{submitLabel}</button>
    </form>
  );
}
