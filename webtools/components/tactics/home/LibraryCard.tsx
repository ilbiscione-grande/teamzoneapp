"use client";

// An item in TeamZone's library, as a card like a project on the start
// page: its first board small, what it is and who shared it, a star to mark
// it a favourite, "Använd" to start a project from it, and a menu with the
// club list, removing and reporting.
import { useEffect, useRef } from "react";
import { libraryKindLabels, librarySummaryLine, type SharedItemSummary, type TacticsClub } from "../../../lib/tactics/library.ts";
import { ProjectThumb, type BoardPreview } from "./ProjectThumb.tsx";

type Props = {
  item: SharedItemSummary & { preview?: BoardPreview | null };
  keeping: TacticsClub[];
  busy: boolean;
  onUse: () => void;
  onFavorite: () => void;
  onPick: (clubId: string, picked: boolean) => void;
  onRemove: () => void;
  onReport: () => void;
};

export function LibraryCard({ item, keeping, busy, onUse, onFavorite, onPick, onRemove, onReport }: Props) {
  // The menu closes on a choice and on a press outside it.
  const menu = useRef<HTMLDetailsElement>(null);
  useEffect(() => {
    const outside = (event: PointerEvent) => { if (menu.current?.open && !menu.current.contains(event.target as Node)) menu.current.open = false; };
    document.addEventListener("pointerdown", outside);
    return () => document.removeEventListener("pointerdown", outside);
  }, []);
  // What is shared only with the club is in its list already; a hidden item is not put there.
  const picks = item.hidden ? [] : keeping.filter(club => !item.club_id);
  const menuItems = picks.length > 0 || item.can_remove || (!item.mine && !item.hidden);
  return (
    <li className="tb-card">
      <button type="button" className="tb-card-picture" tabIndex={-1} aria-hidden="true" onClick={onUse} disabled={busy}>
        <ProjectThumb preview={item.preview} />
        <span className={`tb-card-kind tb-lib-${item.kind}`}>{libraryKindLabels[item.kind]}</span>
      </button>
      <button type="button" className={`tb-pin${item.favorite ? " on" : ""}`} onClick={onFavorite} aria-pressed={item.favorite}
        title={item.favorite ? "Ta bort från favoriter" : "Lägg till i favoriter"}
        aria-label={item.favorite ? `Ta bort ${item.title} från favoriter` : `Lägg ${item.title} i favoriter`}>
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m12 3 2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1-4.4-4.3 6.1-.9z" /></svg>
      </button>
      <div className="tb-card-body">
        <strong className="tb-card-title">{item.title}</strong>
        <span className="tb-card-meta">{librarySummaryLine(item) || `${item.board_count} ${item.board_count === 1 ? "tavla" : "tavlor"}`}</span>
        <span className="tb-card-meta">{[item.starter ? "TeamZone" : `av ${item.author}`, item.club_name && `bara ${item.club_name}`,
          item.version > 1 && `version ${item.version}`, item.hidden && "dold efter rapporter",
          item.picked_by_clubs.length > 0 && "i klubbens lista"].filter(Boolean).join(" · ")}</span>
        <button type="button" className="wt-button small tb-card-use" disabled={busy} onClick={onUse}>{busy ? "Skapar…" : "Använd"}</button>
      </div>
      {menuItems && (
        <details ref={menu} className="tb-card-menu">
          <summary aria-label={`Mer för ${item.title}`} title="Mer">⋯</summary>
          <div role="menu" onClick={() => { if (menu.current) menu.current.open = false; }}>
            {picks.map(club => {
              const picked = item.picked_by_clubs.includes(club.club_id);
              const label = picked ? "Ta bort ur klubbens lista" : "Lägg i klubbens lista";
              return <button key={club.club_id} type="button" role="menuitem" onClick={() => onPick(club.club_id, !picked)}>
                {keeping.length > 1 ? `${label}: ${club.club_name}` : label}</button>;
            })}
            {item.can_remove && <button type="button" role="menuitem" className="danger" onClick={onRemove}>{item.mine ? "Sluta dela" : "Ta bort ur klubbens bibliotek"}</button>}
            {!item.mine && !item.hidden && <button type="button" role="menuitem" onClick={onReport}>Rapportera</button>}
          </div>
        </details>
      )}
    </li>
  );
}
