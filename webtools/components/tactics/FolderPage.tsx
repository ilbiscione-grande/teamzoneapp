"use client";

// A folder's own page: its name and description, its projects in the order
// you set, projects of yours added to it or a new one made in it, and the
// folder removed. Taking a project out of the folder, or removing the
// folder, keeps the projects.
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { folderErrorText, moveInOrder, type Folder } from "../../lib/tactics/folders.ts";
import type { ProjectSummary } from "../../lib/tactics/model.ts";
import { useAccount } from "../account";
import { kindLabels } from "./TopBar.tsx";
import "./tactics.css";

export function FolderPage({ id }: { id: string }) {
  const { client } = useAccount();
  const router = useRouter();
  const [folder, setFolder] = useState<Folder | null | "missing">(null);
  const [mine, setMine] = useState<ProjectSummary[]>([]);
  const [editing, setEditing] = useState(false);
  const [form, setForm] = useState({ name: "", description: "" });
  const [adding, setAdding] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  const load = useCallback(async () => {
    if (!client) return;
    const { data, error: loadError } = await client.schema("api").rpc("get_tactics_folder", { target_folder_id: id });
    if (loadError) { setFolder(loadError.message.includes("not_found") ? "missing" : null); setError(loadError.message.includes("not_found") ? "" : "Mappen kunde inte hämtas."); return; }
    setFolder(data as Folder);
  }, [client, id]);
  useEffect(() => { void load(); }, [load]);
  useEffect(() => {
    client?.schema("api").rpc("list_my_tactics_projects").then(({ data }) => setMine((data as ProjectSummary[] | null) ?? []));
  }, [client]);

  /** Runs a folder RPC, then shows the folder as it now is. */
  const call = async (name: string, args: Record<string, unknown>, fallback: string) => {
    if (!client) return false;
    setBusy(true);
    const { error: callError } = await client.schema("api").rpc(name, args);
    setBusy(false);
    if (callError) { setError(folderErrorText(callError.message, fallback)); return false; }
    setError("");
    await load();
    return true;
  };

  if (folder === "missing") return <p className="wt-status">Mappen finns inte, eller är inte din. <Link className="wt-link" href="/tacticsboard">Till Tacticsboard</Link></p>;
  if (folder === null) return error ? <p role="alert" className="wt-error">{error}</p> : <p className="wt-status">Laddar…</p>;

  const ids = folder.projects.map(project => project.id);
  const addable = mine.filter(project => !ids.includes(project.id));

  const save = async (event: React.FormEvent) => {
    event.preventDefault();
    if (await call("update_tactics_folder", { target_folder_id: id, folder_name: form.name.trim(), folder_description: form.description.trim() },
      "Mappen kunde inte sparas.")) setEditing(false);
  };
  const remove = async () => {
    if (!client || !window.confirm(`Ta bort mappen ${folder.name}? Projekten i den finns kvar i ditt bibliotek.`)) return;
    const { error: removeError } = await client.schema("api").rpc("delete_tactics_folder", { target_folder_id: id });
    if (removeError) { setError("Mappen kunde inte tas bort."); return; }
    router.push("/tacticsboard");
  };

  return (
    <div className="bk-home">
      <p><Link className="wt-link" href="/tacticsboard">← Tacticsboard</Link></p>
      {error && <p role="alert" className="wt-error">{error}</p>}
      <section className="wt-panel" aria-label="Mappen">
        {editing ? (
          <form className="wt-form" onSubmit={save}>
            <label>Namn<input value={form.name} maxLength={120} required onChange={event => setForm({ ...form, name: event.target.value })} /></label>
            <label>Beskrivning<textarea value={form.description} maxLength={2000} rows={4} placeholder="T.ex. spelidén i några rader"
              onChange={event => setForm({ ...form, description: event.target.value })} /></label>
            <div className="wt-actions">
              <button type="submit" className="wt-button small" disabled={busy || !form.name.trim()}>Spara</button>
              <button type="button" className="wt-button secondary small" onClick={() => setEditing(false)}>Avbryt</button>
            </div>
          </form>
        ) : (
          <>
            <h2>{folder.name}</h2>
            {folder.description && <p className="tb-folder-description">{folder.description}</p>}
            <div className="wt-actions">
              <button type="button" className="wt-button secondary small" onClick={() => { setForm({ name: folder.name, description: folder.description }); setEditing(true); }}>Ändra</button>
              <button type="button" className="wt-button secondary small" onClick={() => void remove()}>Ta bort mappen</button>
            </div>
          </>
        )}
      </section>
      <section className="wt-panel" aria-label="Projekten i mappen">
        <h2>Projekt</h2>
        {folder.projects.length === 0 ? <p>Inga projekt i mappen än. Lägg till ett av dina eller skapa ett nytt.</p> : (
          <ol className="bk-resource-list tb-folder-projects">
            {folder.projects.map((project, index) => (
              <li key={project.id}>
                <div>
                  <strong><Link className="wt-link" href={`/tacticsboard/${project.id}`}>{project.name}</Link></strong>
                  <span>{[kindLabels[project.kind], project.team_name, `${project.board_count} ${project.board_count === 1 ? "tavla" : "tavlor"}`].filter(Boolean).join(" · ")}</span>
                </div>
                <div className="wt-actions">
                  <button type="button" className="tb-order" aria-label={`Flytta upp ${project.name}`} disabled={busy || index === 0}
                    onClick={() => void call("order_tactics_folder", { target_folder_id: id, project_ids: moveInOrder(ids, index, -1) }, "Ordningen kunde inte sparas.")}>↑</button>
                  <button type="button" className="tb-order" aria-label={`Flytta ned ${project.name}`} disabled={busy || index === ids.length - 1}
                    onClick={() => void call("order_tactics_folder", { target_folder_id: id, project_ids: moveInOrder(ids, index, 1) }, "Ordningen kunde inte sparas.")}>↓</button>
                  <Link className="wt-button small" href={`/tacticsboard/${project.id}`}>Öppna</Link>
                  <button type="button" className="wt-button secondary small" disabled={busy}
                    onClick={() => void call("remove_tactics_folder_project", { target_folder_id: id, target_project_id: project.id }, "Projektet kunde inte tas ur mappen.")}>Ta bort ur mappen</button>
                </div>
              </li>
            ))}
          </ol>
        )}
        <div className="tb-folder-new">
          {addable.length > 0 && (
            <>
              <label className="tb-field">Lägg till ett av dina projekt
                <select value={adding} onChange={event => setAdding(event.target.value)}>
                  <option value="">Välj projekt</option>
                  {addable.map(project => <option key={project.id} value={project.id}>{project.name}</option>)}
                </select>
              </label>
              <button type="button" className="wt-button small" disabled={busy || !adding}
                onClick={async () => { if (await call("add_tactics_folder_project", { target_folder_id: id, target_project_id: adding }, "Projektet kunde inte läggas i mappen.")) setAdding(""); }}>Lägg till</button>
            </>
          )}
          <Link className="wt-button secondary small" href={`/tacticsboard?mapp=${id}#nytt-projekt`}>Nytt projekt i mappen</Link>
        </div>
      </section>
    </div>
  );
}
