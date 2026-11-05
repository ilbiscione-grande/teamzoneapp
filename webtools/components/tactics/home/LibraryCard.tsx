"use client";

// An item in TeamZone's library, as a card like a project on the start
// page: its first board small, what it is and who shared it, a star to mark
// it a favourite, t("Använd") to start a project from it, and a menu with the
// club list, removing and reporting it.
import { useEffect, useRef } from "react";
import { libraryKindLabels, librarySummaryLine, type SharedItemSummary, type TacticsClub } from "../../../lib/tactics/library.ts";
import { ProjectThumb, type BoardPreview } from "./ProjectThumb.tsx";
import { useT } from "../../language";

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
  const t = useT();
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
        <span className={`tb-card-kind tb-lib-${item.kind}`}>{t(libraryKindLabels[item.kind])}</span>
      </button>
      <button type="button" className={`tb-pin${item.favorite ? " on" : ""}`} onClick={onFavorite} aria-pressed={item.favorite}
        title={item.favorite ? t("Ta bort från favoriter") : t("Lägg till i favoriter")}
        aria-label={item.favorite ? t("Ta bort {name} från favoriter", { name: item.title }) : t("Lägg {name} i favoriter", { name: item.title })}>
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m12 3 2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1-4.4-4.3 6.1-.9z" /></svg>
      </button>
      <div className="tb-card-body">
        <strong className="tb-card-title">{item.title}</strong>
        <span className="tb-card-meta">{librarySummaryLine(item, t) || (item.board_count === 1 ? t("1 tavla") : t("{count} tavlor", { count: item.board_count }))}</span>
        <span className="tb-card-meta">{[item.starter ? "Tacticsboard" : t("av {name}", { name: item.author }), item.club_name && t("bara {name}", { name: item.club_name }),
          item.version > 1 && t("version {number}", { number: item.version }), item.hidden && t("dold efter rapporter"),
          item.picked_by_clubs.length > 0 && t("i klubbens lista")].filter(Boolean).join(" · ")}</span>
        <button type="button" className="wt-button small tb-card-use" disabled={busy} onClick={onUse}>{busy ? t("Skapar…") : t("Använd")}</button>
      </div>
      {menuItems && (
        <details ref={menu} className="tb-card-menu">
          <summary aria-label={t("Mer för {name}", { name: item.title })} title={t("Mer")}>⋯</summary>
          <div role="menu" onClick={() => { if (menu.current) menu.current.open = false; }}>
            {picks.map(club => {
              const picked = item.picked_by_clubs.includes(club.club_id);
              const label = picked ? t("Ta bort ur klubbens lista") : t("Lägg i klubbens lista");
              return <button key={club.club_id} type="button" role="menuitem" onClick={() => onPick(club.club_id, !picked)}>
                {keeping.length > 1 ? `${label}: ${club.club_name}` : label}</button>;
            })}
            {item.can_remove && <button type="button" role="menuitem" className="danger" onClick={onRemove}>{item.mine ? t("Sluta dela") : t("Ta bort ur klubbens bibliotek")}</button>}
            {!item.mine && !item.hidden && <button type="button" role="menuitem" onClick={onReport}>{t("Anmäl")}</button>}
          </div>
        </details>
      )}
    </li>
  );
}
