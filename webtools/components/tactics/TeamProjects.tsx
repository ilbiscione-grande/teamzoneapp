"use client";

// On the start page: the projects other leaders made for the teams you
// lead, to watch or, where the owner lets the team's leaders, to edit. Your
// own are in your library below; none at all, and this is not shown.
import Link from "next/link";
import { useEffect, useState } from "react";
import type { ProjectAccess, ProjectSummary } from "../../lib/tactics/model.ts";
import { useAccount } from "../account";
import { kindLabels } from "./TopBar.tsx";

type TeamProject = ProjectSummary & { access: ProjectAccess; owner_name: string | null };

export function TeamProjects() {
  const { client } = useAccount();
  const [projects, setProjects] = useState<TeamProject[]>([]);
  useEffect(() => {
    // Before the leader-access migration the call fails; nothing is shown then.
    client?.schema("api").rpc("list_team_tactics_projects").then(({ data }) => setProjects((data as TeamProject[] | null) ?? []));
  }, [client]);
  if (projects.length === 0) return null;
  return (
    <section className="wt-panel" aria-label="Lagets tavlor">
      <h2>Lagets tavlor</h2>
      <p className="wt-small">Projekt som andra ledare har gjort för dina lag. Ägaren bestämmer om du kan redigera dem; annars kan du titta och göra en egen kopia.</p>
      <ul className="bk-resource-list">
        {projects.map(project => (
          <li key={project.id}>
            <div>
              <strong>{project.name}</strong>
              <span>{[kindLabels[project.kind], project.team_name, `av ${project.owner_name?.trim() || "en annan ledare"}`,
                project.board_count === 1 ? "1 tavla" : `${project.board_count} tavlor`].filter(Boolean).join(" · ")}</span>
            </div>
            <div className="wt-actions">
              <Link className="wt-button secondary small" href={`/tacticsboard/${project.id}`}>{project.access === "edit" ? "Redigera" : "Titta"}</Link>
            </div>
          </li>
        ))}
      </ul>
    </section>
  );
}
