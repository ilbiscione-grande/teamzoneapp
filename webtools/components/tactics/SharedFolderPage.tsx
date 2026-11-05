// A shared folder's page: its name and description and its projects in the
// owner's order, each opened in the read-only viewer. Drawn on the server.
import Link from "next/link";
import { serverT } from "../../lib/i18n/server.ts";
import { kindNames } from "../../lib/tactics/preview.ts";
import type { SharedFolder } from "../../lib/tactics/shared.ts";
import "./tactics.css";

export async function SharedFolderPage({ token, folder }: { token: string; folder: SharedFolder }) {
  const t = await serverT();
  return (
    <div className="wt-wrap wt-section bk-page">
      <p className="wt-kicker dark">{t("Tacticsboard · delad mapp")}</p>
      <h1 className="wt-page-title">{folder.name}</h1>
      {folder.description && <p className="tb-folder-description">{folder.description}</p>}
      <section className="wt-panel" aria-label={t("Projekten i mappen")}>
        {folder.projects.length === 0 ? <p>{t("Mappen är tom.")}</p> : (
          <ol className="bk-resource-list">
            {folder.projects.map(project => (
              <li key={project.id}>
                <div>
                  <strong><Link className="wt-link" href={`/delad/mapp/${token}/${project.id}`}>{project.name}</Link></strong>
                  <span>{t(kindNames[project.kind])} · {project.board_count === 1 ? t("1 tavla") : t("{count} tavlor", { count: project.board_count })}</span>
                </div>
                <div className="wt-actions">
                  <Link className="wt-button small" href={`/delad/mapp/${token}/${project.id}`}>{t("Visa")}</Link>
                </div>
              </li>
            ))}
          </ol>
        )}
      </section>
    </div>
  );
}
