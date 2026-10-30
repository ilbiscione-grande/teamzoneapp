"use client";

// "Which number are you?" on a shared link: the home team's numbers on the
// boards to pick from, the pick marked on every board (MeMarker) and kept
// in this browser for this link, so a player opening it again is found at
// once. Nothing is sent anywhere.
import { useEffect, useState } from "react";
import { createPortal } from "react-dom";
import { myNumberKey, numbersOn } from "../../lib/tactics/me.ts";
import type { Board } from "../../lib/tactics/model.ts";
import { useEditor } from "./store.ts";

const read = (key: string) => { try { return window.localStorage.getItem(key); } catch { return null; } };
const write = (key: string, value: string | null) => {
  try { if (value === null) window.localStorage.removeItem(key); else window.localStorage.setItem(key, value); } catch { /* private mode: kept for this visit only */ }
};

export function MyNumber({ boards }: { boards: Board[] }) {
  const me = useEditor(state => state.me);
  const [open, setOpen] = useState(false);
  const choices = numbersOn(boards);
  const key = typeof window === "undefined" ? "" : myNumberKey(window.location.pathname);

  // The pick from an earlier visit, if that number is still on the boards.
  useEffect(() => {
    const kept = Number(read(key));
    if (kept && choices.some(choice => choice.number === kept)) useEditor.getState().setMe(kept);
  }, [key]); // eslint-disable-line react-hooks/exhaustive-deps

  if (choices.length === 0) return null;
  const pick = (number: number | null) => {
    useEditor.getState().setMe(number);
    write(key, number === null ? null : String(number));
    setOpen(false);
  };
  return (
    <>
      <button type="button" className="tb-icon tb-pdf tb-me" data-on={me !== null} onClick={() => setOpen(true)}
        title="Välj ditt nummer så syns du på alla tavlor">{me !== null ? `Nr ${me}` : "Jag är…"}</button>
      {open && createPortal(
        <div className="tb-caption-sheet" role="dialog" aria-label="Ditt nummer" onClick={() => setOpen(false)}>
          <div onClick={event => event.stopPropagation()}>
            <div className="tb-modal-head">
              <h2>Vilket nummer är du?</h2>
              <button type="button" className="tb-modal-close" aria-label="Stäng" onClick={() => setOpen(false)}>×</button>
            </div>
            <p className="tb-me-hint">Du markeras med en gul ring på alla tavlor. Valet sparas bara i den här telefonen.</p>
            <div className="tb-me-grid">
              {choices.map(choice => (
                <button key={choice.number} type="button" aria-pressed={me === choice.number} onClick={() => pick(choice.number)}>
                  <strong>{choice.number}</strong>{choice.name && <span>{choice.name}</span>}
                </button>
              ))}
            </div>
            {me !== null && <button type="button" className="tb-link" onClick={() => pick(null)}>Visa ingen</button>}
          </div>
        </div>,
        document.body,
      )}
    </>
  );
}
