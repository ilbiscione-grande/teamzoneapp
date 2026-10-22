"use client";

// The top bar's live button: "Live" to start a lesson, a red mark with the
// number of participants while one runs. The top bar opens the dialog.
import { useLive } from "./live-store.ts";
import "./live.css";

export function LiveButton({ onClick }: { onClick: () => void }) {
  const live = useLive(state => !!state.session);
  const count = useLive(state => state.participants.length);
  return (
    <button type="button" className="tb-live-button tb-wide-only" data-live={live} onClick={onClick}
      title={live ? "Livelektionen pågår" : "Starta en livelektion"} aria-label={live ? `Livelektion, ${count} med` : "Livelektion"}>
      {live ? <><span className="tb-live-dot" aria-hidden="true" />LIVE {count}</> : "Live"}
    </button>
  );
}
