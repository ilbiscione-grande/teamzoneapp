"use client";

// Tacticsboard's start: TeamZone's library, a new project (a match, a
// training or teaching material, for one of your TeamZone teams or none,
// started from ready boards, a template or a favourite), your templates and
// favourites, and your library: all of your projects. A project can also be
// imported from a file. Come from a folder (?mapp=<id>), the new project is
// put in that folder.
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useEffect, useState } from "react";
import { newDocument } from "../../lib/tactics/document.ts";
import type { Board, ProjectKind, ProjectSummary } from "../../lib/tactics/model.ts";
import { boardsFromTemplate, defaultStarterKeys, starterBoard, starterSets } from "../../lib/tactics/templates.ts";
import type { LeaderTeam } from "../../lib/tournament";
import { useAccount } from "../account";
import { kindLabels } from "./TopBar.tsx";
import { useTemplates } from "./use-templates.ts";
import { useSharedLibrary } from "./use-shared-library.ts";
import { MyLibrary } from "./MyLibrary.tsx";
import { useFolders } from "./use-folders.ts";
import { ImportProject } from "./ImportProject.tsx";
import { boardsFromLibrary, libraryKindLabels, librarySummaryLine, noFilters, projectKindOf } from "../../lib/tactics/library.ts";
import "./tactics.css";

export function TacticsHome() {
  const { client } = useAccount();
  const router = useRouter();
  const { folders, addProject } = useFolders();
  const folderId = useSearchParams().get("mapp");
  const folder = folders?.find(item => item.id === folderId) ?? null;
  const [teams, setTeams] = useState<LeaderTeam[]>([]);
  const [form, setForm] = useState({ name: "", kind: "match" as ProjectKind, teamId: "" });
  // "ready" for the ready boards picked below, else a template's id.
  const [start, setStart] = useState("ready");
  const [picked, setPicked] = useState<string[]>(defaultStarterKeys.match);
  const { templates, error: templateError, boardsOf, remove: removeTemplate } = useTemplates();
  // The library's items you marked: additions to your own library.
  const { items: favorites, clubs, search, boardsOf: sharedBoardsOf, favorite } = useSharedLibrary();
  useEffect(() => { void search(noFilters, null, true); }, [search]);
  const unmark = async (id: string) => { if (await favorite(id, false)) void search(noFilters, null, true); };
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    client?.schema("api").rpc("list_tournament_leader_teams").then(({ data }) => setTeams((data as LeaderTeam[] | null) ?? []));
  }, [client]);

  const create = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!client) return;
    setBusy(true); setError("");
    const team = teams.find(item => item.team_id === form.teamId);
    let boards: Board[] | null;
    if (start === "ready") {
      const chosen = starterSets[form.kind].filter(item => picked.includes(item.key));
      boards = chosen.length > 0 ? chosen.map(item => starterBoard(item, team?.team_name)) : newDocument("Tavla 1", team?.team_name).boards;
    } else if (start.startsWith("favorite:")) {
      const item = favorites?.find(entry => entry.id === start.slice(9));
      const found = item ? await sharedBoardsOf(item.id) : null;
      boards = item && found ? boardsFromTemplate(boardsFromLibrary(item, found), team?.team_name) : null;
    } else {
      const found = await boardsOf(start);
      boards = found && boardsFromTemplate(found, team?.team_name);
    }
    if (!boards) { setBusy(false); setError("Mallen kunde inte hämtas. Försök igen."); return; }
    const { data, error: createError } = await client.schema("api").rpc("create_tactics_project", {
      project_name: form.name.trim() || "Namnlöst projekt", project_kind: form.kind, target_team_id: team?.team_id ?? null,
      project_document: { ...newDocument(), boards },
    });
    if (createError) { setBusy(false); setError("Projektet kunde inte skapas. Försök igen."); return; }
    const created = (data as ProjectSummary).id;
    // Not put in the folder, the project is still made; the folder page tells.
    if (folder) await addProject(folder.id, created);
    setBusy(false);
    router.push(`/tacticsboard/${created}`);
  };

  return (
    <div className="bk-home">
      {error && <p role="alert" className="wt-error">{error}</p>}
      <section className="wt-panel">
        <h2>TeamZones bibliotek</h2>
        <p>Övningar, pass och sessioner som tränare delar med varandra, och TeamZones egna. Sök på skede, ålder och spelform.{clubs.length > 0 ? " Där finns också klubbens lista." : ""}</p>
        <Link className="wt-button small" href="/tacticsboard/bibliotek">Sök i TeamZones bibliotek</Link>
      </section>
      <section className="wt-panel" id="nytt-projekt">
        <h2>Nytt projekt</h2>
        {folder && <p className="wt-small">Projektet läggs i mappen <Link className="wt-link" href={`/tacticsboard/mapp/${folder.id}`}>{folder.name}</Link>.</p>}
        <form className="wt-form" onSubmit={create}>
          <label>Namn<input value={form.name} onChange={event => setForm({ ...form, name: event.target.value })} maxLength={120} placeholder="T.ex. Match mot Aneby SK" /></label>
          <div className="bk-times">
            <label>Typ
              <select value={form.kind} onChange={event => {
                const kind = event.target.value as ProjectKind;
                setForm({ ...form, kind });
                setPicked(defaultStarterKeys[kind]);
              }}>
                {Object.entries(kindLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
              </select>
            </label>
            {teams.length > 0 && (
              <label>Lag i TeamZone (frivilligt)
                <select value={form.teamId} onChange={event => setForm({ ...form, teamId: event.target.value })}>
                  <option value="">Inget lag</option>
                  {teams.map(team => <option key={team.team_id} value={team.team_id}>{team.team_name} · {team.club_name}</option>)}
                </select>
              </label>
            )}
          </div>
          <label>Börja från
            <select value={start} onChange={event => {
              setStart(event.target.value);
              const template = templates?.find(item => item.id === event.target.value);
              if (template) setForm({ ...form, kind: template.kind });
              const marked = favorites?.find(entry => `favorite:${entry.id}` === event.target.value);
              if (marked) setForm({ ...form, kind: projectKindOf[marked.kind], name: form.name || marked.title });
            }}>
              <option value="ready">Färdiga tavlor för {kindLabels[form.kind].toLowerCase()}</option>
              {(templates ?? []).map(template => <option key={template.id} value={template.id}>Mall: {template.name}</option>)}
              {(favorites ?? []).map(item => <option key={item.id} value={`favorite:${item.id}`}>Favorit: {item.title}</option>)}
            </select>
          </label>
          {start === "ready" ? (
            <fieldset className="tb-starters">
              <legend>Tavlor att börja med</legend>
              {starterSets[form.kind].map(item => (
                <label key={item.key}>
                  <input type="checkbox" checked={picked.includes(item.key)}
                    onChange={event => setPicked(event.target.checked ? [...picked, item.key] : picked.filter(key => key !== item.key))} />
                  {item.name}
                </label>
              ))}
            </fieldset>
          ) : (
            <p className="wt-small">{start.startsWith("favorite:")
              ? favorites?.find(item => `favorite:${item.id}` === start)?.boards.map(board => board.name).join(", ")
              : templates?.find(item => item.id === start)?.boards.map(board => board.name).join(", ")}</p>
          )}
          <button type="submit" className="wt-button" disabled={busy}>Skapa och öppna</button>
          {teams.length > 0 && <p className="wt-small">Med ett lag hämtar du truppen till tavlan. Senare kan tavlan länkas till lagets aktiviteter i appen.</p>}
        </form>
        <ImportProject onCreated={folder ? id => addProject(folder.id, id) : undefined} />
      </section>
      {templates && templates.length > 0 && (
        <section className="wt-panel">
          <h2>Dina mallar</h2>
          {templateError && <p role="alert" className="wt-error">{templateError}</p>}
          <ul className="bk-resource-list">
            {templates.map(template => (
              <li key={template.id}>
                <div>
                  <strong>{template.name}</strong>
                  <span>{[kindLabels[template.kind], template.boards.map(board => board.name).join(", ")].join(" · ")}</span>
                </div>
                <div className="wt-actions">
                  <button type="button" className="wt-button secondary small"
                    onClick={() => { if (window.confirm(`Ta bort mallen ${template.name}?`)) { if (start === template.id) setStart("ready"); void removeTemplate(template.id); } }}>Ta bort</button>
                </div>
              </li>
            ))}
          </ul>
        </section>
      )}
      {favorites && favorites.length > 0 && (
        <section className="wt-panel" aria-label="Dina favoriter">
          <h2>Dina favoriter</h2>
          <p className="wt-small">Övningar, pass och sessioner ur biblioteket som du har markerat. Börja ett nytt projekt från dem ovan.</p>
          <ul className="bk-resource-list">
            {favorites.map(item => (
              <li key={item.id}>
                <div>
                  <strong>{item.title}</strong>
                  <span>{[libraryKindLabels[item.kind], librarySummaryLine(item), item.starter ? "TeamZone" : `av ${item.author}`].filter(Boolean).join(" · ")}</span>
                </div>
                <div className="wt-actions">
                  <button type="button" className="wt-button secondary small" onClick={() => { if (start === `favorite:${item.id}`) setStart("ready"); void unmark(item.id); }}>Ta bort favorit</button>
                </div>
              </li>
            ))}
          </ul>
        </section>
      )}
      <MyLibrary />
    </div>
  );
}
