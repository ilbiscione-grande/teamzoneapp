"use client";

// The top bar's live button: t("Live") to start a lesson, a red mark with the
// number of participants while one runs. The top bar opens the dialog.
// Under it, a word when the lesson is about to end for want of activity,
// or has ended by itself.
import { useLive } from "./live-store.ts";
import "./live.css";
import { useT } from "../../language";

export function LiveButton({ onClick }: { onClick: () => void }) {
  const t = useT();
  const live = useLive(state => !!state.session);
  const count = useLive(state => state.participants.length);
  return (
    <>
      <LiveNotice />
      <button type="button" className="tb-live-button tb-wide-only" data-live={live} onClick={onClick}
        title={live ? t("Livelektionen pågår") : t("Starta en livelektion")} aria-label={live ? t("Livelektion, {count} med", { count }) : t("Livelektion")}>
        {live ? <><span className="tb-live-dot" aria-hidden="true" />LIVE {count}</> : t("Live")}
      </button>
    </>
  );
}

/** Shown at the top of the screen, in the editor and when presenting. */
export function LiveNotice() {
  const t = useT();
  const idle = useLive(state => state.idle);
  const notice = useLive(state => state.notice);
  const live = useLive(state => !!state.session);
  if (live && idle === "warning") {
    return (
      <div className="tb-live-notice" role="alert">
        {t("Livelektionen avslutas om fem minuter om inget händer.")}
        <button type="button" className="wt-button small" onClick={() => useLive.getState().markActivity()}>{t("Fortsätt lektionen")}</button>
      </div>
    );
  }
  if (!notice) return null;
  return (
    <div className="tb-live-notice" role="status">
      {t(notice)}
      <button type="button" className="tb-modal-close" aria-label={t("Stäng")} onClick={() => useLive.getState().set({ notice: "" })}>×</button>
    </div>
  );
}
