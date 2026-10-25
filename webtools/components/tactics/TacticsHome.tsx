"use client";

// Your Tacticsboard projects, and a new one: a match, a training or teaching
// material, for one of your TeamZone teams or none, started from ready
// boards for its kind or from one of your templates. Your templates too.
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { newDocument } from "../../lib/tactics/document.ts";
import type { Board, ProjectKind, ProjectSummary } from "../../lib/tactics/model.ts";
import { boardsFromTemplate, defaultStarterKeys, starterBoard, starterSets } from "../../lib/tactics/templates.ts";
import type { LeaderTeam } from "../../lib/tournament";
import { useAccount } from "../account";
import { kindLabels } from "./TopBar.tsx";
import { useTemplates } from "./use-templates.ts";
import { useLibrary } from "./use-library.ts";
import { useSharedLibrary } from "./use-shared-library.ts";
import { LibraryShareDialog } from "./LibraryShareDialog.tsx";
import type { LibraryItemSummary } from "../../lib/tactics/library.ts";
import { boardsFromLibrary, libraryKindLabels, librarySummaryLine, noFilters, projectKindOf } from "../../lib/tactics/library.ts";
import "./tactics.css";

export function TacticsHome() {
  const { client } = useAccount();
  const router = useRouter();
  const [projects, setProjects] = useState<ProjectSummary[] | null>(null);
  const [teams, setTeams] = useState<LeaderTeam[]>([]);
  const [form, setForm] = useState({ name: "", kind: "match" as ProjectKind, teamId: "" });
  // "ready" for the ready boards picked below, else a template's id.
  const [start, setStart] = useState("ready");
  const [picked, setPicked] = useState<string[]>(defaultStarterKeys.match);
  const { templates, error: templateError, boardsOf, remove: removeTemplate } = useTemplates();
  const { items: library, error: libraryError, boardsOf: libraryBoardsOf, remove: removeLibraryItem, reload: reloadLibrary } = useLibrary();
  // The library's items you marked: additions to your own library.
  const { items: favorites, error: shareError, clubs, search, boardsOf: sharedBoardsOf, share, unshare, favorite } = useSharedLibrary();
  useEffect(() => { void search(noFilters, null, true); }, [search]);
  const unmark = async (id: string) => { if (await favorite(id, false)) void search(noFilters, null, true); };
  const [sharing, setSharing] = useState<LibraryItemSummary | null>(null);
  const unshareItem = async (sharedId: string, title: string) => {
    if (!window.confirm(`Sluta dela ${title}? Den tas bort ur biblioteket för dem du delat den med men finns kvar i ditt. De som redan använt den behåller sina kopior.`)) return;
    if (await unshare(sharedId)) void reloadLibrary();
  };
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  const load = useCallback(async () => {
    if (!client) return;
    const { data, error: loadError } = await client.schema("api").rpc("list_my_tactics_projects");
    if (loadError) { setError("Projekten kunde inte hämtas."); return; }
    setProjects(data as ProjectSummary[]);
  }, [client]);
  useEffect(() => { void load(); }, [load]);
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
    } else if (start.startsWith("library:")) {
      const item = library?.find(entry => entry.id === start.slice(8));
      const found = item ? await libraryBoardsOf(item.id) : null;
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
    setBusy(false);
    if (createError) { setError("Projektet kunde inte skapas. Försök igen."); return; }
    router.push(`/tacticsboard/${(data as ProjectSummary).id}`);
  };

  const remove = async (project: ProjectSummary) => {
    if (!client || !window.confirm(`Ta bort ${project.name}? Det går inte att ångra.`)) return;
    const { error: removeError } = await client.schema("api").rpc("delete_tactics_project", { target_project_id: project.id });
    if (removeError) { setError("Projektet kunde inte tas bort."); return; }
    void load();
  };

  return (
    <div className="bk-home">
      {error && <p role="alert" className="wt-error">{error}</p>}
      <section className="wt-panel">
        <h2>TeamZones bibliotek</h2>
        <p>Övningar, pass och sessioner som tränare delar med varandra, och TeamZones egna. Sök på skede, ålder och spelform.{clubs.length > 0 ? " Där finns också klubbens lista." : ""}</p>
        <Link className="wt-button small" href="/tacticsboard/bibliotek">Sök i TeamZones bibliotek</Link>
      </section>
      <section className="wt-panel">
        <h2>Nytt projekt</h2>
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
              const item = library?.find(entry => `library:${entry.id}` === event.target.value);
              if (item) setForm({ ...form, kind: projectKindOf[item.kind], name: form.name || item.title });
              const marked = favorites?.find(entry => `favorite:${entry.id}` === event.target.value);
              if (marked) setForm({ ...form, kind: projectKindOf[marked.kind], name: form.name || marked.title });
            }}>
              <option value="ready">Färdiga tavlor för {kindLabels[form.kind].toLowerCase()}</option>
              {(templates ?? []).map(template => <option key={template.id} value={template.id}>Mall: {template.name}</option>)}
              {(library ?? []).map(item => <option key={item.id} value={`library:${item.id}`}>{libraryKindLabels[item.kind]}: {item.title}</option>)}
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
              : start.startsWith("library:")
              ? library?.find(item => `library:${item.id}` === start)?.boards.map(board => board.name).join(", ")
              : templates?.find(item => item.id === start)?.boards.map(board => board.name).join(", ")}</p>
          )}
          <button type="submit" className="wt-button" disabled={busy}>Skapa och öppna</button>
          {teams.length > 0 && <p className="wt-small">Med ett lag hämtar du truppen till tavlan. Senare kan tavlan länkas till lagets aktiviteter i appen.</p>}
        </form>
      </section>
      {sharing && (
        <LibraryShareDialog item={sharing} clubs={clubs} onClose={() => setSharing(null)}
          onShare={async clubId => { const done = await share(sharing.id, clubId); if (done) void reloadLibrary(); return done; }} />
      )}
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
      {library && library.length > 0 && (
        <section className="wt-panel" aria-label="Ditt bibliotek">
          <h2>Ditt bibliotek</h2>
          <p className="wt-small">Övningar, pass och sessioner du har sparat. Börja ett nytt projekt från dem ovan.</p>
          {(libraryError || shareError) && <p role="alert" className="wt-error">{libraryError || shareError}</p>}
          <ul className="bk-resource-list">
            {library.map(item => (
              <li key={item.id}>
                <div>
                  <strong>{item.title}</strong>
                  <span>{[libraryKindLabels[item.kind], librarySummaryLine(item), item.version > 1 && `version ${item.version}`].filter(Boolean).join(" · ")}</span>
                  {item.shared && (
                    <span>{[item.shared.club_name ? `Delad med ${item.shared.club_name}` : "Delad med hela communityn",
                      item.shared.hidden ? "dold efter rapporter"
                        : item.shared.current ? `version ${item.shared.version}` : "du har ändrat den sedan"].join(" · ")}</span>
                  )}
                </div>
                <div className="wt-actions">
                  {!item.shared ? (
                    <button type="button" className="wt-button secondary small" onClick={() => setSharing(item)}>Dela…</button>
                  ) : (
                    <>
                      {!item.shared.hidden && (
                        <button type="button" className="wt-button secondary small" onClick={() => setSharing(item)}>
                          {item.shared.current ? "Ändra delning…" : "Dela nya versionen…"}
                        </button>
                      )}
                      <button type="button" className="wt-button secondary small" onClick={() => void unshareItem(item.shared!.id, item.title)}>Sluta dela</button>
                    </>
                  )}
                  <button type="button" className="wt-button secondary small"
                    onClick={() => { if (window.confirm(`Ta bort ${item.title} ur biblioteket?`)) { if (start === `library:${item.id}`) setStart("ready"); void removeLibraryItem(item.id); } }}>Ta bort</button>
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
      <section className="wt-panel">
        <h2>Dina projekt</h2>
        {projects === null ? <p className="wt-status">Laddar…</p> : projects.length === 0 ? <p>Inga projekt än.</p> : (
          <ul className="bk-resource-list">
            {projects.map(project => (
              <li key={project.id}>
                <div>
                  <strong><Link className="wt-link" href={`/tacticsboard/${project.id}`}>{project.name}</Link></strong>
                  <span>{[kindLabels[project.kind], project.team_name, `${project.board_count} ${project.board_count === 1 ? "tavla" : "tavlor"}`,
                    `ändrat ${new Date(project.updated_at).toLocaleDateString("sv-SE", { day: "numeric", month: "short" })}`].filter(Boolean).join(" · ")}</span>
                </div>
                <div className="wt-actions">
                  <Link className="wt-button small" href={`/tacticsboard/${project.id}`}>Öppna</Link>
                  <button type="button" className="wt-button secondary small" onClick={() => void remove(project)}>Ta bort</button>
                </div>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
