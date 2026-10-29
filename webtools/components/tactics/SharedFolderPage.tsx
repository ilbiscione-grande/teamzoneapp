// A shared folder's page: its name and description and its projects in the
// owner's order, each opened in the read-only viewer. Drawn on the server.
import Link from "next/link";
import type { ProjectKind } from "../../lib/tactics/model.ts";
import type { SharedFolder } from "../../lib/tactics/shared.ts";
import "./tactics.css";

// As TopBar's kindLabels; that module is the client's, out of a server page's reach.
const kinds: Record<ProjectKind, string> = { match: "Match", training: "Träning", education: "Utbildning" };

export function SharedFolderPage({ token, folder }: { token: string; folder: SharedFolder }) {
  return (
    <div className="wt-wrap wt-section bk-page">
      <p className="wt-kicker dark">Tacticsboard · delad mapp</p>
      <h1 className="wt-page-title">{folder.name}</h1>
      {folder.description && <p className="tb-folder-description">{folder.description}</p>}
      <section className="wt-panel" aria-label="Projekten i mappen">
        {folder.projects.length === 0 ? <p>Mappen är tom.</p> : (
          <ol className="bk-resource-list">
            {folder.projects.map(project => (
              <li key={project.id}>
                <div>
                  <strong><Link className="wt-link" href={`/delad/mapp/${token}/${project.id}`}>{project.name}</Link></strong>
                  <span>{kinds[project.kind]} · {project.board_count} {project.board_count === 1 ? "tavla" : "tavlor"}</span>
                </div>
                <div className="wt-actions">
                  <Link className="wt-button small" href={`/delad/mapp/${token}/${project.id}`}>Visa</Link>
                </div>
              </li>
            ))}
          </ol>
        )}
      </section>
    </div>
  );
}
