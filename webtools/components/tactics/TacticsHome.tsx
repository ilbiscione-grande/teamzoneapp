"use client";

// Tacticsboard's start: a new project (guided in a dialog, NewProjectDialog)
// or one quickly by kind, TeamZone's library, and your projects as a grid
// of cards with their first board small. The ones you pin come first, then
// your folders, your projects and the team's projects other leaders made,
// all found with one search. A project can also be imported from a file.
// Come from a folder (?mapp=<id>), the new project is put in that folder.
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useEffect, useState } from "react";
import { removalNote } from "../../lib/tactics/folders.ts";
import type { ProjectKind } from "../../lib/tactics/model.ts";
import { noFilters } from "../../lib/tactics/library.ts";
import type { LeaderTeam } from "../../lib/tournament";
import { useAccount } from "../account";
import { kindLabels } from "./TopBar.tsx";
import { useTemplates } from "./use-templates.ts";
import { useSharedLibrary } from "./use-shared-library.ts";
import { useFolders } from "./use-folders.ts";
import { FolderCards } from "./FolderCards.tsx";
import { FolderPicker } from "./FolderPicker.tsx";
import { ImportProject } from "./ImportProject.tsx";
import { HomeFilterBar } from "./home/HomeFilterBar.tsx";
import { kindHints, NewProjectDialog } from "./home/NewProjectDialog.tsx";
import { ProjectCard, type HomeProject } from "./home/ProjectCard.tsx";
import { noHomeFilters, teamMatches, useHomeProjects } from "./home/use-home-projects.ts";
import "./tactics.css";
import "./home/home.css";

export function TacticsHome() {
  const { client } = useAccount();
  const { folders, error: folderError, create: createFolder, addProject, reload: reloadFolders } = useFolders();
  const folderId = useSearchParams().get("mapp");
  const folder = folders?.find(item => item.id === folderId) ?? null;
  const [teams, setTeams] = useState<LeaderTeam[]>([]);
  const { templates, error: templateError, boardsOf, remove: removeTemplate } = useTemplates();
  // The library's items you marked, to start a project from.
  const { items: favorites, search, boardsOf: sharedBoardsOf } = useSharedLibrary();
  useEffect(() => { void search(noFilters, null, true); }, [search]);
  const [filters, setFilters] = useState(noHomeFilters);
  const { mine, team, error, pin, remove, unpublish } = useHomeProjects(filters);
  // The dialog's preset kind, or "pick" to begin with the kind; null when closed.
  const [creating, setCreating] = useState<ProjectKind | "pick" | null>(null);
  const [picking, setPicking] = useState<HomeProject | null>(null);
  const [importing, setImporting] = useState(false);

  useEffect(() => {
    client?.schema("api").rpc("list_tournament_leader_teams").then(({ data }) => setTeams((data as LeaderTeam[] | null) ?? []));
  }, [client]);
  // Come from a folder's "Nytt projekt", the dialog is open at once.
  useEffect(() => { if (folderId) setCreating("pick"); }, [folderId]);

  const removeProject = async (project: HomeProject) => {
    const published = (project.published ?? []).length > 0 ? " Det du publicerat från projektet finns kvar i TeamZones bibliotek." : "";
    if (await remove(project, `Ta bort ${project.name}? Det går inte att ångra.${published}${removalNote(project.folders ?? [])}`) && project.folders?.length) {
      void reloadFolders();
    }
  };

  const teamShown = team.filter(project => teamMatches(project, filters));
  const pinned = [...(mine ?? []), ...teamShown].filter(project => project.pinned);
  const own = (mine ?? []).filter(project => !project.pinned);
  const others = teamShown.filter(project => !project.pinned);
  const filtered = Object.values(filters).some(value => value !== "");
  const nothingYet = mine !== null && mine.length === 0 && team.length === 0 && !filtered;
  const card = (project: HomeProject) => (
    <ProjectCard key={project.id} project={project} onPin={pin} onFolders={setPicking}
      onRemove={project.access === undefined ? removeProject : undefined} onUnpublish={unpublish} />
  );

  return (
    <div className="tb-home">
      <div className="tb-home-actions">
        <button type="button" className="wt-button" onClick={() => setCreating("pick")}>
          <span aria-hidden="true">+</span> Nytt projekt
        </button>
        <Link className="wt-button secondary" href="/tacticsboard/bibliotek">TeamZones bibliotek</Link>
        <button type="button" className="wt-button secondary" aria-expanded={importing} onClick={() => setImporting(!importing)}>Importera</button>
      </div>
      {importing && <ImportProject folderId={folder?.id} onCreated={folder ? id => addProject(folder.id, id) : undefined} />}
      {templateError && <p role="alert" className="wt-error">{templateError}</p>}

      {nothingYet ? (
        <section className="tb-welcome" aria-label="Kom igång">
          <h2>Kom igång</h2>
          <p>Vad vill du göra först? Du väljer sedan vad projektet börjar från, så du slipper rita allt själv.</p>
          <div className="tb-quick big">
            {(Object.keys(kindLabels) as ProjectKind[]).map(kind => (
              <button key={kind} type="button" className="tb-quick-card" onClick={() => setCreating(kind)}>
                <span className={`tb-choice-icon tb-kind-${kind}`} aria-hidden="true">{kindLabels[kind].slice(0, 1)}</span>
                <strong>Ny {kindLabels[kind].toLowerCase()}</strong>
                <span>{kindHints[kind]}</span>
              </button>
            ))}
            <Link className="tb-quick-card" href="/tacticsboard/bibliotek">
              <span className="tb-choice-icon tb-kind-library" aria-hidden="true">B</span>
              <strong>Hämta från biblioteket</strong>
              <span>Övningar, pass och sessioner som andra tränare och TeamZone delar.</span>
            </Link>
          </div>
        </section>
      ) : (
        <div className="tb-quick" aria-label="Snabbstart">
          <span className="tb-quick-label">Snabbstart:</span>
          {(Object.keys(kindLabels) as ProjectKind[]).map(kind => (
            <button key={kind} type="button" className="tb-chip" onClick={() => setCreating(kind)}>
              <span className={`tb-dot tb-kind-${kind}`} aria-hidden="true" />Ny {kindLabels[kind].toLowerCase()}
            </button>
          ))}
        </div>
      )}

      {!nothingYet && <HomeFilterBar filters={filters} onChange={setFilters} kinds={kindLabels} />}
      {error && <p role="alert" className="wt-error">{error}</p>}

      {pinned.length > 0 && (
        <section aria-labelledby="tb-pinned">
          <h2 id="tb-pinned" className="tb-home-heading">Fästa</h2>
          <ul className="tb-grid">{pinned.map(card)}</ul>
        </section>
      )}

      {!filtered && !nothingYet && <FolderCards folders={folders} error={folderError} create={createFolder} />}

      {!nothingYet && (
        <section aria-labelledby="tb-mine">
          <div className="tb-home-head">
            <h2 id="tb-mine" className="tb-home-heading">Mina projekt</h2>
            {mine && <span className="tb-count">{mine.length}</span>}
          </div>
          {mine === null ? <p className="wt-status">Laddar…</p> : own.length === 0 ? (
            <p className="tb-empty">{filtered ? "Inget av dina projekt passar sökningen." : pinned.length > 0 ? "Alla dina projekt är fästa ovan." : "Inga egna projekt än."}</p>
          ) : (
            <ul className="tb-grid">{own.map(card)}</ul>
          )}
        </section>
      )}

      {others.length > 0 && (
        <section aria-labelledby="tb-team">
          <div className="tb-home-head">
            <h2 id="tb-team" className="tb-home-heading">Lagets tavlor</h2>
            <span className="tb-count">{teamShown.length}</span>
          </div>
          <p className="wt-small">Projekt som andra ledare har gjort för dina lag. Ägaren bestämmer om du kan redigera dem; annars kan du titta och göra en egen kopia.</p>
          <ul className="tb-grid">{others.map(card)}</ul>
        </section>
      )}

      {picking && (
        <FolderPicker projectId={picking.id} projectName={picking.name} current={picking.folders ?? []}
          onClose={changed => { setPicking(null); if (changed) { setFilters(current => ({ ...current })); void reloadFolders(); } }} />
      )}
      {creating && (
        <NewProjectDialog teams={teams} folder={folder} templates={templates} templateBoards={boardsOf}
          removeTemplate={id => void removeTemplate(id)} favorites={favorites} favoriteBoards={sharedBoardsOf} addToFolder={addProject}
          kind={creating === "pick" ? undefined : creating} onClose={() => setCreating(null)} />
      )}
    </div>
  );
}
