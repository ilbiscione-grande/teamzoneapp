"use client";

// Tacticsboard opens only with a trial or a subscription. Without them the
// page is locked and offers to subscribe; nothing is deleted, and links the
// person has shared keep working for others. The database enforces this
// (internal.require_tacticsboard); this explains it.
import { useState } from "react";
import { accessNote, launchOfferOpen, lockedText, prices } from "../../lib/tactics/access.ts";
import { useBilling, useTacticsboardAccess } from "./use-tacticsboard-access.ts";
import { tacticsboardTermsUrl } from "../../lib/support.ts";

export function SubscribeButtons() {
  const { busy, error, subscribe } = useBilling();
  const offer = launchOfferOpen();
  return (
    <>
      <div className="wt-actions">
        <button type="button" className="wt-button" disabled={busy} onClick={() => subscribe("month")}>
          {prices.month.label}
        </button>
        <button type="button" className="wt-button secondary" disabled={busy} onClick={() => subscribe("year")}>
          {prices.year.label}{offer ? ` – ${prices.launch.label}` : ""}
        </button>
      </div>
      {offer && <p className="wt-small">Halva priset första året gäller årsabonnemang som tecknas senast 31 december 2026.</p>}
      <p className="wt-small">Priserna är inklusive moms. Du betalar hos Stripe och kan säga upp när du vill. Läs <a href={tacticsboardTermsUrl}>villkoren för Tacticsboard</a>.</p>
      {error && <p className="wt-error" role="alert">{error}</p>}
    </>
  );
}

/** During the trial it offers to subscribe; after a failed payment or a cancellation, Stripe's portal. */
function AccessNote({ note, trial, grace }: { note: string; trial: boolean; grace: boolean }) {
  const { busy, error, manage } = useBilling();
  const [open, setOpen] = useState(false);
  return (
    <div className="wt-note" role="status">
      {note}{" "}
      {trial
        ? <button type="button" className="wt-link-button" aria-expanded={open} onClick={() => setOpen(!open)}>Prenumerera</button>
        : <button type="button" className="wt-link-button" disabled={busy} onClick={manage}>{grace ? "Uppdatera kortet" : "Fortsätt prenumerera"}</button>}
      {error && <span className="wt-error"> {error}</span>}
      {open && <SubscribeButtons />}
    </div>
  );
}

/**
 * Wraps a Tacticsboard page. `note` shows the trial's days or a failed
 * payment above it; `lockedFrame` gives the full-screen editor a page frame
 * for the locked state.
 */
export function RequireTacticsboard(
  { children, note = true, lockedFrame = false }: { children: React.ReactNode; note?: boolean; lockedFrame?: boolean },
) {
  const { access, error } = useTacticsboardAccess();
  const frame = (content: React.ReactNode) => lockedFrame ? <div className="wt-wrap wt-section">{content}</div> : content;
  if (error) return frame(<p className="wt-status" role="alert">{error}</p>);
  if (!access) return frame(<p className="wt-status">Laddar…</p>);
  if (access.access_mode !== "write") {
    const { title, text } = lockedText(access);
    return frame(
      <section className="wt-panel" aria-labelledby="tb-locked-title">
        <h2 id="tb-locked-title">{title}</h2>
        <p>{text}</p>
        <SubscribeButtons />
      </section>,
    );
  }
  const line = note ? accessNote(access) : "";
  return (
    <>
      {line && <AccessNote note={line} trial={access.source === "trial"} grace={access.source === "grace"} />}
      {children}
    </>
  );
}
