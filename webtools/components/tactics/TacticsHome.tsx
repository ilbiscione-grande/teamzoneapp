"use client";

// Your Tacticsboard projects, and a new one: a match, a training or teaching
// material, for one of your TeamZone teams or none.
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { newDocument } from "../../lib/tactics/document.ts";
import type { ProjectKind, ProjectSummary } from "../../lib/tactics/model.ts";
import type { LeaderTeam } from "../../lib/tournament";
import { useAccount } from "../account";
import { kindLabels } from "./TopBar.tsx";

export function TacticsHome() {
  const { client } = useAccount();
  const router = useRouter();
  const [projects, setProjects] = useState<ProjectSummary[] | null>(null);
  const [teams, setTeams] = useState<LeaderTeam[]>([]);
  const [form, setForm] = useState({ name: "", kind: "match" as ProjectKind, teamId: "" });
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
    const firstBoard = form.kind === "training" ? "Övning 1" : form.kind === "education" ? "Princip 1" : "Uppställning";
    const { data, error: createError } = await client.schema("api").rpc("create_tactics_project", {
      project_name: form.name.trim() || "Namnlöst projekt", project_kind: form.kind, target_team_id: team?.team_id ?? null,
      project_document: newDocument(firstBoard, team?.team_name),
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
        <h2>Nytt projekt</h2>
        <form className="wt-form" onSubmit={create}>
          <label>Namn<input value={form.name} onChange={event => setForm({ ...form, name: event.target.value })} maxLength={120} placeholder="T.ex. Match mot Aneby SK" /></label>
          <div className="bk-times">
            <label>Typ
              <select value={form.kind} onChange={event => setForm({ ...form, kind: event.target.value as ProjectKind })}>
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
          <button type="submit" className="wt-button" disabled={busy}>Skapa och öppna</button>
          {teams.length > 0 && <p className="wt-small">Med ett lag hämtar du truppen till tavlan. Senare kan tavlan länkas till lagets aktiviteter i appen.</p>}
        </form>
      </section>
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
