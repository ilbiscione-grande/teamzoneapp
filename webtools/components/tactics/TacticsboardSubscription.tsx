"use client";

// Tacticsboard on the account page: the trial's days, the subscription and
// its next payment, and Stripe's portal for card, receipts and cancelling.
// Back from Stripe Checkout (?betalning=klar) it waits for the webhook.
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useEffect, useState } from "react";
import { subscriptionSummary } from "../../lib/tactics/access.ts";
import { SubscribeButtons } from "./RequireTacticsboard.tsx";
import { useBilling, useTacticsboardAccess } from "./use-tacticsboard-access.ts";

export function TacticsboardSubscription() {
  const { access, error, reload } = useTacticsboardAccess({ startTrial: false });
  const billing = useBilling();
  const result = useSearchParams().get("betalning");
  const [waited, setWaited] = useState(0);
  const waiting = result === "klar" && access !== null && access.source !== "subscription" && waited < 10;

  // Stripe tells the database through the webhook, usually within seconds.
  useEffect(() => {
    if (!waiting) return;
    const timer = setTimeout(() => { setWaited(n => n + 1); void reload(); }, 2000);
    return () => clearTimeout(timer);
  }, [waiting, waited, reload]);

  if (error) return <p className="wt-error" role="alert">{error}</p>;
  if (!access) return <p className="wt-status">Laddar…</p>;
  const summary = subscriptionSummary(access);
  return (
    <div className="tb-subscription">
      <h3>Tacticsboard</h3>
      {result === "klar" && (
        <p className="wt-note" role="status">
          {access.source === "subscription" ? "Tack! Prenumerationen är igång."
            : waiting ? "Tack! Betalningen är klar. Prenumerationen kopplas på…"
            : "Tack! Betalningen är klar. Det kan dröja en stund innan prenumerationen syns här. Ladda om sidan om en minut."}
        </p>
      )}
      {result === "avbruten" && <p className="wt-note" role="status">Betalningen avbröts. Inget har dragits.</p>}
      {summary.lines.map(line => <p key={line}>{line}</p>)}
      {summary.tryIt && <Link className="wt-button" href="/tacticsboard">Prova gratis</Link>}
      {summary.manage && (
        <>
          <div className="wt-actions">
            <button type="button" className={summary.subscribe ? "wt-button secondary" : "wt-button"} disabled={billing.busy}
              onClick={billing.manage}>
              {summary.manage === "card" ? "Uppdatera kortet" : "Hantera betalning och kvitton"}
            </button>
          </div>
          <p className="wt-small">Hos Stripe byter du kort, ser dina kvitton och säger upp prenumerationen.</p>
          {billing.error && <p className="wt-error" role="alert">{billing.error}</p>}
        </>
      )}
      {summary.subscribe && <SubscribeButtons />}
    </div>
  );
}
