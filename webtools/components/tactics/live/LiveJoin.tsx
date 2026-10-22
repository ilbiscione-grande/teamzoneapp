"use client";

// Joining a live lesson: the code (from the link, or typed), a name, then
// in. Signed in to Webtools, the account joins under its own name; else a
// guest joins with a name, where the host allows guests.
import type { SupabaseClient } from "@supabase/supabase-js";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { joinError, normalizeCode, type LiveJoined } from "../../../lib/tactics/live.ts";
import { useAccount } from "../../account";
import "../tactics.css";
import "./live.css";
import { signedInGuest } from "./guest-client.ts";
import { LiveViewer } from "./LiveViewer.tsx";

export function LiveJoin({ initialCode }: { initialCode: string | null }) {
  const router = useRouter();
  const account = useAccount();
  const [code, setCode] = useState(initialCode ?? "");
  const [name, setName] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [loginNeeded, setLoginNeeded] = useState(false);
  const [joined, setJoined] = useState<{ client: SupabaseClient; data: LiveJoined; guest: boolean } | null>(null);
  const signedIn = !!account.session && !!account.client;
  useEffect(() => { if (signedIn && account.displayName) setName(current => current || account.displayName); }, [signedIn, account.displayName]);

  const join = async (event: React.FormEvent) => {
    event.preventDefault();
    const normalized = normalizeCode(code);
    if (!normalized) { setError("Koden är sex tecken, bokstäver och siffror."); return; }
    if (normalized !== initialCode) router.replace(`/live/${normalized}`);
    setBusy(true); setError(""); setLoginNeeded(false);
    let client = signedIn ? account.client! : null;
    if (!client) {
      const guest = await signedInGuest();
      if ("error" in guest) { setBusy(false); setError(guest.error); setLoginNeeded(true); return; }
      client = guest.client;
    }
    const { data, error: joinFailure } = await client.schema("api").rpc("join_tactics_live", { target_code: normalized, participant_name: name.trim() });
    setBusy(false);
    if (joinFailure) {
      setError(joinError(joinFailure.message));
      setLoginNeeded(joinFailure.message.includes("login_required"));
      return;
    }
    setJoined({ client, data: data as LiveJoined, guest: !signedIn });
  };

  if (joined) return <LiveViewer client={joined.client} joined={joined.data} guest={joined.guest} />;
  if (!account.ready) return <p className="wt-wrap wt-section wt-status">Laddar…</p>;
  const returnTo = normalizeCode(code) ? `/live/${normalizeCode(code)}` : "/";
  return (
    <div className="wt-wrap wt-section wt-narrow">
      <section className="wt-panel tb-live-entry">
        <h1>Livelektion</h1>
        <p>Följ tavlan som läraren visar den, på din egen skärm.</p>
        <form className="wt-form" onSubmit={join}>
          <label>Kod<input value={code} onChange={event => setCode(event.target.value)} maxLength={8} autoCapitalize="characters" autoComplete="off" placeholder="T.ex. K7P2QX" required /></label>
          <label>Ditt namn<input value={name} onChange={event => setName(event.target.value)} maxLength={40} required={!signedIn} placeholder="Så ser läraren dig" /></label>
          <button type="submit" className="wt-button" disabled={busy}>{busy ? "Går med…" : "Gå med"}</button>
          {error && <p className="wt-error" role="alert">{error}</p>}
          {loginNeeded && !signedIn && <Link className="wt-button secondary" href={`/logga-in?returnTo=${encodeURIComponent(returnTo)}`}>Logga in</Link>}
          {signedIn ? <p className="wt-small">Du går med som inloggad.</p> : <p className="wt-small">Har du ett TeamZone-konto? <Link className="wt-link" href={`/logga-in?returnTo=${encodeURIComponent(returnTo)}`}>Logga in</Link> först.</p>}
        </form>
      </section>
    </div>
  );
}
