"use client";

// A shared link's small parts: whether it is watched on a phone, the
// buttons on the board's corner (full screen, the arena on or off), the
// board's description in a sheet, sharing the link on, and their icons.
import { useEffect, useState } from "react";
import type { Board } from "../../lib/tactics/model.ts";
import { useEditor } from "./store.ts";

const PHONE = "(max-width: 760px)";

export const isPhone = () => typeof window !== "undefined" && window.matchMedia(PHONE).matches;

/** A narrow screen: the pitch upright and without its arena from the start. */
export function usePhone(): boolean {
  const [phone, setPhone] = useState(isPhone);
  useEffect(() => {
    const query = window.matchMedia(PHONE);
    const changed = () => setPhone(query.matches);
    query.addEventListener("change", changed);
    return () => query.removeEventListener("change", changed);
  }, []);
  return phone;
}

/** The arena or training ground on or off; only for a board that has one. */
export function SurroundingsButton({ board }: { board: Board }) {
  const plain = useEditor(state => state.plain);
  if (!board.surroundings || board.surroundings === "none") return null;
  const label = board.surroundings === "arena" ? "arenan" : "träningsplanen runt";
  return (
    <button type="button" aria-pressed={!plain} onClick={() => useEditor.getState().setPlain(!plain)}
      aria-label={plain ? `Visa ${label}` : `Dölj ${label}`} title={plain ? `Visa ${label}` : `Dölj ${label}`}>
      <StandsIcon />
    </button>
  );
}

/** Shares the link through the phone's own sheet; where there is none, onFallback (the QR code). */
export async function shareLink(title: string, onFallback: () => void) {
  const data = { title, url: window.location.href };
  if (!navigator.share || (navigator.canShare && !navigator.canShare(data))) { onFallback(); return; }
  try { await navigator.share(data); } catch { /* closed without sharing */ }
}

export function AboutSheet({ board, onClose }: { board: Board; onClose: () => void }) {
  return (
    <div className="tb-caption-sheet" role="dialog" aria-label="Om tavlan" onClick={onClose}>
      <div onClick={event => event.stopPropagation()}>
        <div className="tb-modal-head">
          <h2>{board.name || "Om tavlan"}</h2>
          <button type="button" className="tb-modal-close" aria-label="Stäng" onClick={onClose}>×</button>
        </div>
        <p>{board.description?.trim()}</p>
      </div>
    </div>
  );
}

const icon = { viewBox: "0 0 24 24", width: 20, height: 20, fill: "none", stroke: "currentColor", strokeWidth: 2, strokeLinecap: "round", strokeLinejoin: "round", "aria-hidden": true } as const;

export function ShareIcon() {
  return <svg {...icon}><circle cx="18" cy="5" r="3" /><circle cx="6" cy="12" r="3" /><circle cx="18" cy="19" r="3" /><path d="m8.6 13.5 6.8 4M15.4 6.5l-6.8 4" /></svg>;
}

export function TextIcon() {
  return <svg {...icon}><path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z" /><path d="M14 3v6h6M8 13h8M8 17h6" /></svg>;
}

export function InfoIcon() {
  return <svg {...icon}><circle cx="12" cy="12" r="9" /><path d="M12 11v5M12 8h.01" /></svg>;
}

export function PersonIcon() {
  return <svg {...icon}><circle cx="12" cy="8" r="4" /><path d="M4 21a8 8 0 0 1 16 0" /></svg>;
}

export function FullScreenIcon() {
  return <svg {...icon}><path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5" /></svg>;
}

function StandsIcon() {
  return <svg {...icon}><path d="M3 20h18M5 20v-6l7-3 7 3v6M8 20v-4h8v4" /><path d="M12 11V5l4 1.5L12 8" /></svg>;
}
