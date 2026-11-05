"use client";

// A project on the start page: its first board small, its name and what it
// is, a pin to keep it first, and a menu with what else can be done with it.
// Your own projects show what of them is published and the folders they are
// in; the team's show who made them and whether you may edit.
import Link from "next/link";
import { useEffect, useRef } from "react";
import type { FolderRef } from "../../../lib/tactics/folders.ts";
import { libraryKindLabels } from "../../../lib/tactics/library.ts";
import type { ProjectAccess, ProjectSummary } from "../../../lib/tactics/model.ts";
import { useLanguage } from "../../language";
import { kindLabels } from "../TopBar.tsx";
import { PublishedIcon } from "../PublishedIcon.tsx";
import { ProjectThumb, type BoardPreview } from "./ProjectThumb.tsx";

export type Published = {
  item_id: string; kind: "exercise" | "plan" | "lesson"; title: string; board_id: string | null; shared_id: string;
  version: number; hidden: boolean; current: boolean; club_id: string | null; club_name: string | null;
};
export type HomeProject = ProjectSummary & {
  preview?: BoardPreview | null; pinned?: boolean;
  // Your own.
  published?: Published[]; folders?: FolderRef[];
  // The team's.
  access?: ProjectAccess; owner_name?: string | null;
};

type Props = {
  project: HomeProject;
  onPin: (project: HomeProject) => void;
  onFolders?: (project: HomeProject) => void;
  onRemove?: (project: HomeProject) => void;
  onUnpublish?: (item: Published) => void;
  // Your own: picked with shift, and dragged onto a folder.
  selected?: boolean;
  onSelect?: (project: HomeProject) => void;
  onDrag?: (project: HomeProject, event: React.DragEvent) => void;
};

export const changedOn = (at: string, intl: string) => new Date(at).toLocaleDateString(intl, { day: "numeric", month: "short" });

export function ProjectCard({ project, onPin, onFolders, onRemove, onUnpublish, selected, onSelect, onDrag }: Props) {
  const { t, intl } = useLanguage();
  // The menu closes on a choice and on a press outside it.
  const menu = useRef<HTMLDetailsElement>(null);
  useEffect(() => {
    const outside = (event: PointerEvent) => { if (menu.current?.open && !menu.current.contains(event.target as Node)) menu.current.open = false; };
    document.addEventListener("pointerdown", outside);
    return () => document.removeEventListener("pointerdown", outside);
  }, []);
  const href = `/tacticsboard/${project.id}`;
  const team = project.access !== undefined;
  const published = project.published ?? [];
  const meta = [t(kindLabels[project.kind]), project.team_name, project.board_count === 1 ? t("1 tavla") : t("{count} tavlor", { count: project.board_count })].filter(Boolean).join(" · ");
  return (
    <li className={`tb-card${selected ? " selected" : ""}`} aria-selected={onSelect ? !!selected : undefined}
      draggable={!!onDrag} onDragStart={onDrag && (event => onDrag(project, event))}
      // Shift and a click picks the card (and others with it) instead of opening it.
      onClickCapture={onSelect && (event => { if (event.shiftKey) { event.preventDefault(); event.stopPropagation(); onSelect(project); } })}>
      <Link className="tb-card-picture" href={href} tabIndex={-1} aria-hidden="true">
        <ProjectThumb preview={project.preview} />
        <span className={`tb-card-kind tb-kind-${project.kind}`}>{t(kindLabels[project.kind])}</span>
      </Link>
      <button type="button" className={`tb-pin${project.pinned ? " on" : ""}`} onClick={() => onPin(project)}
        aria-pressed={!!project.pinned} title={project.pinned ? t("Ta bort från fästa") : t("Fäst överst")}
        aria-label={project.pinned ? t("Ta bort {name} från fästa", { name: project.name }) : t("Fäst {name} överst", { name: project.name })}>
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m12 3 2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1-4.4-4.3 6.1-.9z" /></svg>
      </button>
      <div className="tb-card-body">
        <Link className="tb-card-title" href={href}>
          {project.name}
          {[...new Set(published.map(item => item.club_name ?? ""))].map(club => <PublishedIcon key={club} clubName={club || null} />)}
        </Link>
        <span className="tb-card-meta">{meta}</span>
        <span className="tb-card-meta">
          {team ? `${t("av {name}", { name: project.owner_name?.trim() || t("en annan ledare") })} · ${project.access === "edit" ? t("du kan redigera") : t("du kan titta")}` : t("ändrat {date}", { date: changedOn(project.updated_at, intl) })}
        </span>
        {project.folders && project.folders.length > 0 && (
          <span className="tb-folder-tags" aria-label={t("Mappar")}>
            {project.folders.map(folder => <Link key={folder.id} className="tb-folder-tag" href={`/tacticsboard/mapp/${folder.id}`}>{folder.name}</Link>)}
          </span>
        )}
      </div>
      {!team && (
        <details ref={menu} className="tb-card-menu">
          <summary aria-label={t("Mer för {name}", { name: project.name })} title={t("Mer")}>⋯</summary>
          <div role="menu" onClick={() => { if (menu.current) menu.current.open = false; }}>
            <Link role="menuitem" href={href}>{t("Öppna")}</Link>
            {onFolders && <button type="button" role="menuitem" onClick={() => onFolders(project)}>{t("Mappar…")}</button>}
            {published.map(item => onUnpublish && (
              <button key={item.item_id} type="button" role="menuitem" onClick={() => onUnpublish(item)}
                title={item.hidden ? t("Dold efter rapporter") : item.current ? t("Version {number}", { number: item.version }) : t("Ändrad sedan den publicerades")}>
                {t("Sluta publicera {kind}: {title}", { kind: t(libraryKindLabels[item.kind]).toLowerCase(), title: item.title })}
              </button>
            ))}
            {onRemove && <button type="button" role="menuitem" className="danger" onClick={() => onRemove(project)}>{t("Ta bort")}</button>}
          </div>
        </details>
      )}
    </li>
  );
}
