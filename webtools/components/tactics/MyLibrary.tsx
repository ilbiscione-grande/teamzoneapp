"use client";

// Mitt bibliotek: all your projects, matches, trainings and teaching
// material alike, filtered as TeamZone's library is (words, kind, the part
// of the session, the phase of the game, age class and game form). Each
// project shows with an icon whether something of it is published, and
// for whom; what is published can be taken back here. Publishing is done
// in the project, under Tavlan → Publicera. Your folders show above the
// projects; each project shows the folders it is in and can be put in others.
import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { removalNote, type FolderRef } from "../../lib/tactics/folders.ts";
import {
  ageClasses, ageClassLabels, gameFormLabels, gameForms, libraryKindLabels, partLabels, phaseLabels,
} from "../../lib/tactics/library.ts";
import type { AgeClass, ExercisePart, GameForm, GamePhase, ProjectKind, ProjectSummary } from "../../lib/tactics/model.ts";
import { useAccount } from "../account";
import { kindLabels } from "./TopBar.tsx";
import { PublishedIcon } from "./PublishedIcon.tsx";
import { FolderCards } from "./FolderCards.tsx";
import { FolderPicker } from "./FolderPicker.tsx";
import { useFolders } from "./use-folders.ts";

type Published = {
  item_id: string; kind: "exercise" | "plan" | "lesson"; title: string; board_id: string | null; shared_id: string;
  version: number; hidden: boolean; current: boolean; club_id: string | null; club_name: string | null;
};
// Folders come with the migration 20261223090000; missing before it.
type MyProject = ProjectSummary & { published: Published[]; folders?: FolderRef[] };
type Filters = { text: string; kind: ProjectKind | ""; part: ExercisePart | ""; phase: GamePhase | ""; age: AgeClass | ""; form: GameForm | "" };
const none: Filters = { text: "", kind: "", part: "", phase: "", age: "", form: "" };

export function MyLibrary() {
  const { client } = useAccount();
  const [filters, setFilters] = useState<Filters>(none);
  const [projects, setProjects] = useState<MyProject[] | null>(null);
  const [error, setError] = useState("");
  const { folders, error: folderError, create, reload: reloadFolders } = useFolders();
  const [picking, setPicking] = useState<MyProject | null>(null);
  const set = (patch: Partial<Filters>) => setFilters(current => ({ ...current, ...patch }));

  const load = useCallback(async (current: Filters) => {
    if (!client) return;
    const { data, error: loadError } = await client.schema("api").rpc("search_my_tactics_projects", {
      search_text: current.text.trim().slice(0, 100), project_kind: current.kind || null, exercise_part: current.part || null,
      game_phase: current.phase || null, age_class: current.age || null, game_form: current.form || null,
    });
    if (loadError) { setError("Ditt bibliotek kunde inte hämtas."); setProjects([]); return; }
    setError("");
    setProjects(data as MyProject[]);
  }, [client]);
  useEffect(() => {
    const timer = window.setTimeout(() => void load(filters), filters.text ? 300 : 0);
    return () => window.clearTimeout(timer);
  }, [filters, load]);

  const remove = async (project: MyProject) => {
    if (!client || !window.confirm(`Ta bort ${project.name}? Det går inte att ångra.${project.published.length > 0
      ? " Det du publicerat från projektet finns kvar i TeamZones bibliotek." : ""}${removalNote(project.folders ?? [])}`)) return;
    const { error: removeError } = await client.schema("api").rpc("delete_tactics_project", { target_project_id: project.id });
    if (removeError) { setError("Projektet kunde inte tas bort."); return; }
    void load(filters);
    if (project.folders?.length) void reloadFolders();
  };

  const unpublish = async (item: Published) => {
    if (!client || !window.confirm(`Sluta publicera ${item.title}? De som redan använt den behåller sina kopior.`)) return;
    const { error: removeError } = await client.schema("api").rpc("unshare_tactics_item", { target_shared_id: item.shared_id });
    if (removeError) { setError("Det kunde inte tas bort ur TeamZones bibliotek."); return; }
    void load(filters);
  };

  const filtered = Object.entries(filters).some(([, value]) => value !== "");
  return (
    <section className="wt-panel" aria-label="Mitt bibliotek">
      <h2>Mitt bibliotek</h2>
      <p className="wt-small">Alla dina projekt. Publicera en övning, ett pass eller en session i ett projekt under Tavlan → Publicera.</p>
      <FolderCards folders={folders} error={folderError} create={create} />
      {picking && (
        <FolderPicker projectId={picking.id} projectName={picking.name} current={picking.folders ?? []}
          onClose={changed => { setPicking(null); if (changed) { void load(filters); void reloadFolders(); } }} />
      )}
      <h3 className="tb-projects-heading">Projekt</h3>
      <div className="wt-form">
        <label>Sök<input value={filters.text} maxLength={100} placeholder="Namn, tavlor, beskrivning" onChange={event => set({ text: event.target.value })} /></label>
        <div className="bk-times tb-filters">
          <label>Typ
            <select value={filters.kind} onChange={event => set({ kind: event.target.value as Filters["kind"] })}>
              <option value="">Alla</option>
              {Object.entries(kindLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
            </select>
          </label>
          <label>Del av passet
            <select value={filters.part} onChange={event => set({ part: event.target.value as Filters["part"] })}>
              <option value="">Alla</option>
              {Object.entries(partLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
            </select>
          </label>
          <label>Skede
            <select value={filters.phase} onChange={event => set({ phase: event.target.value as Filters["phase"] })}>
              <option value="">Alla</option>
              {Object.entries(phaseLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
            </select>
          </label>
          <label>Ålder
            <select value={filters.age} onChange={event => set({ age: event.target.value as Filters["age"] })}>
              <option value="">Alla</option>
              {ageClasses.map(age => <option key={age} value={age}>{ageClassLabels[age]}</option>)}
            </select>
          </label>
          <label>Spelform
            <select value={filters.form} onChange={event => set({ form: event.target.value as Filters["form"] })}>
              <option value="">Alla</option>
              {gameForms.map(form => <option key={form} value={form}>{gameFormLabels[form]}</option>)}
            </select>
          </label>
        </div>
      </div>
      {error && <p role="alert" className="wt-error">{error}</p>}
      {projects === null ? <p className="wt-status">Laddar…</p> : projects.length === 0 ? (
        <p>{filtered ? "Inget projekt passar filtren." : "Inga projekt än. Skapa ett ovan."}</p>
      ) : (
        <ul className="bk-resource-list">
          {projects.map(project => (
            <li key={project.id}>
              <div>
                <strong>
                  <Link className="wt-link" href={`/tacticsboard/${project.id}`}>{project.name}</Link>
                  {/* One icon per audience the project has published for. */}
                  {[...new Set(project.published.map(item => item.club_name ?? ""))].map(club => (
                    <PublishedIcon key={club} clubName={club || null} />
                  ))}
                </strong>
                <span>{[kindLabels[project.kind], project.team_name, `${project.board_count} ${project.board_count === 1 ? "tavla" : "tavlor"}`,
                  `ändrat ${new Date(project.updated_at).toLocaleDateString("sv-SE", { day: "numeric", month: "short" })}`].filter(Boolean).join(" · ")}</span>
                {project.folders && project.folders.length > 0 && (
                  <span className="tb-folder-tags" aria-label="Mappar">
                    {project.folders.map(folder => <Link key={folder.id} className="tb-folder-tag" href={`/tacticsboard/mapp/${folder.id}`}>{folder.name}</Link>)}
                  </span>
                )}
                {project.published.map(item => (
                  <span key={item.item_id} className="tb-published-line">
                    <PublishedIcon clubName={item.club_name} />
                    {libraryKindLabels[item.kind]}: {item.title}
                    {item.hidden ? " · dold efter rapporter" : item.current ? ` · version ${item.version}` : " · ändrad sedan den publicerades"}
                    <button type="button" className="wt-link tb-inline-button" onClick={() => void unpublish(item)}>Sluta publicera</button>
                  </span>
                ))}
              </div>
              <div className="wt-actions">
                <Link className="wt-button small" href={`/tacticsboard/${project.id}`}>Öppna</Link>
                <button type="button" className="wt-button secondary small" onClick={() => setPicking(project)}>Mappar…</button>
                <button type="button" className="wt-button secondary small" onClick={() => void remove(project)}>Ta bort</button>
              </div>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
