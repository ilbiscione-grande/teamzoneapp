"use client";

// Ending the account from the account page. The account-deletion function
// checks first, ends any subscription at once, erases the data and the
// sign-in; then Webtools signs out.
import { useState } from "react";
import { accountDeletionErrorText, deletionWord } from "../lib/account";
import { useAccount } from "./account";

export function AccountDeletion() {
  const { client, signOut } = useAccount();
  const [open, setOpen] = useState(false);
  const [word, setWord] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function endAccount(event: React.FormEvent) {
    event.preventDefault();
    if (!client || busy || word.trim().toUpperCase() !== deletionWord) return;
    setBusy(true);
    setError("");
    const { error: invokeError } = await client.functions.invoke("account-deletion", { body: { confirm: deletionWord } });
    if (!invokeError) {
      await signOut();
      window.location.assign("/");
      return;
    }
    const answer = await (invokeError as { context?: Response }).context?.json?.().catch(() => null);
    setError(accountDeletionErrorText(answer?.error ?? ""));
    setBusy(false);
  }

  return (
    <section className="wt-panel" aria-labelledby="delete-title">
      <h2 id="delete-title">Avsluta kontot</h2>
      {!open ? (
        <button type="button" className="wt-button secondary" onClick={() => setOpen(true)}>Avsluta kontot</button>
      ) : (
        <form className="wt-form" onSubmit={endAccount}>
          <p>Kontot och allt du har gjort i Tacticsboard tas bort: projekt, mappar, mallar, delade länkar och det du har publicerat i biblioteket.</p>
          <p>Har du en prenumeration avslutas den direkt, utan återbetalning för resten av perioden. Dina kvitton finns kvar hos Stripe.</p>
          <p><strong>Det går inte att ångra.</strong></p>
          <label>
            Skriv {deletionWord} för att bekräfta
            <input value={word} onChange={event => setWord(event.target.value)} autoComplete="off" disabled={busy} />
          </label>
          {error && <p className="wt-error" role="alert">{error}</p>}
          <div className="wt-actions">
            <button type="submit" className="wt-button" disabled={busy || word.trim().toUpperCase() !== deletionWord}>
              {busy ? "Avslutar…" : "Avsluta kontot för gott"}
            </button>
            <button type="button" className="wt-button secondary" disabled={busy}
              onClick={() => { setOpen(false); setWord(""); setError(""); }}>Avbryt</button>
          </div>
        </form>
      )}
    </section>
  );
}
