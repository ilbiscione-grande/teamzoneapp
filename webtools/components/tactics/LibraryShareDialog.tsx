"use client";

// Sharing an item of your library (decision package 13): with the whole
// community in TeamZone's library, or only with one of your clubs. Shared
// before, it shares the latest version, and who sees it may change. Others
// may use and copy what you share (TBL-05); your name shows (TBL-15).
import { useEffect, useState } from "react";
import type { LibraryItemSummary, TacticsClub } from "../../lib/tactics/library.ts";

export function LibraryShareDialog({ item, clubs, onShare, onClose }: {
  item: LibraryItemSummary;
  clubs: TacticsClub[];
  onShare: (clubId: string | null) => Promise<boolean>;
  onClose: () => void;
}) {
  const [target, setTarget] = useState<string>(item.shared?.club_id ?? "community");
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => { if (event.key === "Escape") onClose(); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  const submit = async (event: React.FormEvent) => {
    event.preventDefault();
    setBusy(true);
    const done = await onShare(target === "community" ? null : target);
    setBusy(false);
    if (done) onClose();
  };

  return (
    <div className="tb-modal" role="dialog" aria-modal="true" aria-label="Dela" onClick={event => { if (event.target === event.currentTarget) onClose(); }}>
      <form className="tb-modal-card" onSubmit={submit}>
        <div className="tb-modal-head">
          <h2>Dela {item.title}</h2>
          <button type="button" className="tb-modal-close" aria-label="Stäng" onClick={onClose}>×</button>
        </div>
        <div className="tb-field" role="radiogroup" aria-label="Vem som ser den">
          <label className="tb-check">
            <input type="radio" name="share-target" checked={target === "community"} onChange={() => setTarget("community")} />
            Hela communityn: alla med Tacticsboard i TeamZones bibliotek
          </label>
          {clubs.map(club => (
            <label key={club.club_id} className="tb-check">
              <input type="radio" name="share-target" checked={target === club.club_id} onChange={() => setTarget(club.club_id)} />
              Bara {club.club_name}: klubbens ledare
            </label>
          ))}
        </div>
        <p className="tb-hint">Den delas med ditt namn, och de som ser den får använda och kopiera den. Kopplingar till spelare följer inte med.
          {item.shared ? " Den senaste versionen delas, och de som redan använt den behåller sina kopior." : ""}</p>
        <div className="tb-actions">
          <button type="submit" className="wt-button small" disabled={busy}>{busy ? "Delar…" : item.shared ? "Dela den senaste versionen" : "Dela"}</button>
          <button type="button" className="wt-button secondary small" onClick={onClose}>Avbryt</button>
        </div>
      </form>
    </div>
  );
}
