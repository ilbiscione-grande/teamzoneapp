"use client";

// The person's access to Tacticsboard. The first visit starts the 7-day
// trial (api.start_tacticsboard_trial is idempotent and starts it only once);
// afterwards it only reads the status.
import { useCallback, useEffect, useState } from "react";
import { useAccount } from "../account";
import { billingErrorText, type Interval, type TacticsAccess } from "../../lib/tactics/access.ts";

/** `startTrial` is false where only the status is shown, such as the account page. */
export function useTacticsboardAccess({ startTrial = true }: { startTrial?: boolean } = {}) {
  const { client } = useAccount();
  const [access, setAccess] = useState<TacticsAccess | null>(null);
  const [error, setError] = useState("");

  const load = useCallback(async () => {
    if (!client) return;
    setError("");
    const read = await client.schema("api").rpc("get_my_tacticsboard_access");
    let next = read.data as TacticsAccess | null;
    if (startTrial && !read.error && next?.trial_available) {
      const started = await client.schema("api").rpc("start_tacticsboard_trial");
      next = started.error ? next : (started.data as TacticsAccess);
    }
    if (read.error || !next) { setError("Tacticsboard går inte att öppna just nu. Försök igen om en stund."); return; }
    setAccess(next);
  }, [client, startTrial]);

  useEffect(() => { void load(); }, [load]);

  return { access, error, reload: load };
}

/** Opens Stripe Checkout or the Customer Portal; returns an error text, or navigates away. */
export function useBilling() {
  const { client } = useAccount();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  const open = useCallback(async (body: Record<string, string>) => {
    if (!client || busy) return;
    setBusy(true);
    setError("");
    const { data, error: invokeError } = await client.functions.invoke("tacticsboard-billing", { body });
    if (!invokeError && typeof data?.url === "string") { window.location.assign(data.url); return; }
    const answer = await (invokeError as { context?: Response } | null)?.context?.json?.().catch(() => null);
    setError(billingErrorText(answer?.error ?? ""));
    setBusy(false);
  }, [client, busy]);

  return {
    busy,
    error,
    subscribe: (interval: Interval) => open({ action: "checkout", interval, idempotencyKey: crypto.randomUUID() }),
    manage: () => open({ action: "portal" }),
  };
}
