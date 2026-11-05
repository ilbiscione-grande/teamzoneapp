"use client";

// t("Ångra köpet") on the account page (2 kap. 10 a § distansavtalslagen): the
// person confirms their name and the purchase, confirms the withdrawal, and
// gets the time it was received, here and as a receipt by e-mail.
import { useState } from "react";
import { useAccount } from "../account";
import { useLanguage } from "../language";
import { type WithdrawalStatus, withdrawalFacts, withdrawalReceivedText } from "../../lib/tactics/withdrawal.ts";

const failed = "Det gick inte just nu. Försök igen, eller mejla support@teamzoneapp.se. Ett mejl räcker också som ånger.";

export function WithdrawPurchase({ onReceived }: { onReceived: () => void }) {
  const { client, displayName } = useAccount();
  const language = useLanguage();
  const { t } = language;
  const [status, setStatus] = useState<WithdrawalStatus | null>(null);
  const [open, setOpen] = useState(false);
  const [name, setName] = useState(displayName);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function call(body: Record<string, string>) {
    if (!client) return null;
    setBusy(true);
    setError("");
    const { data, error: invokeError } = await client.functions.invoke("tacticsboard-billing", { body });
    setBusy(false);
    if (invokeError || typeof data?.state !== "string") { setError(t(failed)); return null; }
    return data as WithdrawalStatus;
  }

  async function start() {
    setOpen(true);
    setStatus(await call({ action: "withdrawal_status" }));
  }

  async function confirm(event: React.FormEvent) {
    event.preventDefault();
    if (busy || !name.trim()) return;
    const answer = await call({ action: "withdraw", name: name.trim() });
    if (!answer) return;
    setStatus(answer);
    if (answer.state === "received") onReceived();
  }

  if (!open) {
    return <button type="button" className="wt-button secondary" onClick={start}>{t("Ångra köpet")}</button>;
  }
  if (!status) {
    return error ? <p className="wt-error" role="alert">{error}</p> : <p className="wt-status">{t("Laddar…")}</p>;
  }
  if (status.state === "none") return <p className="wt-note" role="status">{t("Det finns inget köp att ångra.")}</p>;
  if (status.state === "received") return <p className="wt-note" role="status">{withdrawalReceivedText(status, language)}</p>;
  if (status.state === "expired") {
    return <p className="wt-note" role="status">{t("Ångerfristen gick ut {date}. Du kan säga upp prenumerationen under Hantera betalning och kvitton.", { date: status.last_day })}</p>;
  }
  return (
    <form className="wt-form" onSubmit={confirm}>
      <h4>{t("Ångra köpet")}</h4>
      <p>{withdrawalFacts(status, language)}</p>
      <label>
        {t("Ditt namn")}
        <input value={name} onChange={event => setName(event.target.value)} autoComplete="name" maxLength={200} required disabled={busy} />
      </label>
      <p className="wt-small">{t("Prenumerationen avslutas direkt. Har du betalat får du tillbaka pengarna inom 14 dagar, med avdrag för en proportionell del av priset för den betalda tiden. Mottagningsbeviset skickas till {email}.", { email: status.email })}</p>
      {error && <p className="wt-error" role="alert">{error}</p>}
      <div className="wt-actions">
        <button type="submit" className="wt-button" disabled={busy || !name.trim()}>{busy ? "Skickar…" : t("Bekräfta att jag ångrar köpet")}</button>
        <button type="button" className="wt-button secondary" disabled={busy} onClick={() => { setOpen(false); setStatus(null); setError(""); }}>{t("Avbryt")}</button>
      </div>
    </form>
  );
}
