"use client";

// The group work's time: what is left, counting down, for everyone; and for
// the host, setting it. Nothing happens by itself when it runs out; the
// host decides when the groups are done.
import type { SupabaseClient } from "@supabase/supabase-js";
import { useEffect, useState } from "react";
import { deadlineFrom, groupError, timeLeft } from "../../../lib/tactics/live-groups.ts";
import { useGroup } from "./group-store.ts";
import { useT } from "../../language";

const MINUTES = [2, 3, 5, 10, 15];

/** What is left, ticking; "Tiden är ute" once out. Nothing without a time. */
export function TimeLeft() {
  const t = useT();
  const deadline = useGroup(store => store.deadline);
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (deadline === null) return;
    const timer = window.setInterval(() => setNow(Date.now()), 500);
    return () => window.clearInterval(timer);
  }, [deadline]);
  if (deadline === null) return null;
  const out = deadline <= now;
  return <span className="tb-live-time" data-out={out} role="timer">{out ? t("Tiden är ute") : t("{time} kvar", { time: timeLeft(deadline, now) })}</span>;
}

/** The host sets the time from now, or takes it away. */
export function GroupTimeControl({ client, sessionId }: { client: SupabaseClient; sessionId: string }) {
  const t = useT();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const set = async (minutes: number | null) => {
    setBusy(true); setError("");
    const { error: failure } = await client.schema("api").rpc("set_tactics_live_groups_timer", { target_session_id: sessionId, minutes });
    setBusy(false);
    if (failure) { setError(t(groupError(failure.message))); return; }
    useGroup.getState().set({ deadline: deadlineFrom(minutes === null ? null : minutes * 60) });
  };
  return (
    <div className="tb-live-group-time">
      <label className="tb-field">{t("Tid för grupperna")}
        <select value="" disabled={busy} onChange={event => { if (event.target.value) void set(event.target.value === "none" ? null : Number(event.target.value)); }}>
          <option value="">{t("Välj tid…")}</option>
          {MINUTES.map(minutes => <option key={minutes} value={minutes}>{t("{count} min", { count: minutes })}</option>)}
          <option value="none">{t("Ingen tid")}</option>
        </select>
      </label>
      <TimeLeft />
      {error && <p className="wt-error" role="alert">{error}</p>}
    </div>
  );
}
