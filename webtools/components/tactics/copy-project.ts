// A whole project copied into a new one of your own: the same kind, team and
// boards under "<name> (kopia)". Share links, pins, folders and what is
// published stay with the original.
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Translate } from "../../lib/i18n/translate.ts";
import type { ProjectKind } from "../../lib/tactics/model.ts";

export type ProjectSource = { name: string; kind: ProjectKind; teamId: string | null; document: unknown };

export const copyName = (name: string, t: Translate) =>
  t("{name} (kopia)", { name: name.trim() || t("Namnlöst projekt") }).slice(0, 120);

/** The copy's id, or null when it could not be made. */
export async function copyProject(client: SupabaseClient, source: ProjectSource, t: Translate): Promise<string | null> {
  const { data, error } = await client.schema("api").rpc("create_tactics_project", {
    project_name: copyName(source.name, t), project_kind: source.kind,
    target_team_id: source.teamId, project_document: source.document,
  });
  return error ? null : (data as { id: string }).id;
}

/** A project from the list, read whole first (the list has no boards). */
export async function copyProjectById(client: SupabaseClient, projectId: string, t: Translate): Promise<string | null> {
  const { data, error } = await client.schema("api").rpc("get_tactics_project", { target_project_id: projectId });
  if (error || !data) return null;
  const project = data as { name: string; kind: ProjectKind; teamzone_team_id: string | null; document: unknown };
  return copyProject(client, { name: project.name, kind: project.kind, teamId: project.teamzone_team_id, document: project.document }, t);
}
