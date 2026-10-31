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
};

export const changedOn = (at: string) => new Date(at).toLocaleDateString("sv-SE", { day: "numeric", month: "short" });

export function ProjectCard({ project, onPin, onFolders, onRemove, onUnpublish }: Props) {
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
  const meta = [kindLabels[project.kind], project.team_name, project.board_count === 1 ? "1 tavla" : `${project.board_count} tavlor`].filter(Boolean).join(" · ");
  return (
    <li className="tb-card">
      <Link className="tb-card-picture" href={href} tabIndex={-1} aria-hidden="true">
        <ProjectThumb preview={project.preview} />
        <span className={`tb-card-kind tb-kind-${project.kind}`}>{kindLabels[project.kind]}</span>
      </Link>
      <button type="button" className={`tb-pin${project.pinned ? " on" : ""}`} onClick={() => onPin(project)}
        aria-pressed={!!project.pinned} title={project.pinned ? "Ta bort från fästa" : "Fäst överst"}
        aria-label={project.pinned ? `Ta bort ${project.name} från fästa` : `Fäst ${project.name} överst`}>
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m12 3 2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1-4.4-4.3 6.1-.9z" /></svg>
      </button>
      <div className="tb-card-body">
        <Link className="tb-card-title" href={href}>
          {project.name}
          {[...new Set(published.map(item => item.club_name ?? ""))].map(club => <PublishedIcon key={club} clubName={club || null} />)}
        </Link>
        <span className="tb-card-meta">{meta}</span>
        <span className="tb-card-meta">
          {team ? `av ${project.owner_name?.trim() || "en annan ledare"} · ${project.access === "edit" ? "du kan redigera" : "du kan titta"}` : `ändrat ${changedOn(project.updated_at)}`}
        </span>
        {project.folders && project.folders.length > 0 && (
          <span className="tb-folder-tags" aria-label="Mappar">
            {project.folders.map(folder => <Link key={folder.id} className="tb-folder-tag" href={`/tacticsboard/mapp/${folder.id}`}>{folder.name}</Link>)}
          </span>
        )}
      </div>
      {!team && (
        <details ref={menu} className="tb-card-menu">
          <summary aria-label={`Mer för ${project.name}`} title="Mer">⋯</summary>
          <div role="menu" onClick={() => { if (menu.current) menu.current.open = false; }}>
            <Link role="menuitem" href={href}>Öppna</Link>
            {onFolders && <button type="button" role="menuitem" onClick={() => onFolders(project)}>Mappar…</button>}
            {published.map(item => onUnpublish && (
              <button key={item.item_id} type="button" role="menuitem" onClick={() => onUnpublish(item)}
                title={item.hidden ? "Dold efter rapporter" : item.current ? `Version ${item.version}` : "Ändrad sedan den publicerades"}>
                Sluta publicera {libraryKindLabels[item.kind].toLowerCase()}: {item.title}
              </button>
            ))}
            {onRemove && <button type="button" role="menuitem" className="danger" onClick={() => onRemove(project)}>Ta bort</button>}
          </div>
        </details>
      )}
    </li>
  );
}
