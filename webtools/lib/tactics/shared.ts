// A shared Tacticsboard link, read on Webtools' server with the secret key:
// the database lets only the server read it. A link is to a project (or
// one board of it), or to a folder of projects.
import { createClient } from "@supabase/supabase-js";
import type { Board, Branding, ProjectKind } from "./model.ts";

export type SharedTactics = {
  name: string;
  kind: ProjectKind;
  updated_at: string;
  team_name: string | null;
  /** The one board the link is for, or null for the whole project. */
  board_id: string | null;
  boards: Board[];
  /** Read through a folder's link: the folder's name. */
  folder_name?: string;
  /** The club logo on the pitch; absent before the branding migration. */
  branding?: Branding | null;
};

export type SharedFolder = {
  name: string;
  description: string;
  updated_at: string;
  projects: { id: string; name: string; kind: ProjectKind; board_count: number; updated_at: string }[];
};

const isToken = (token: string) => /^[0-9a-f]{40}$/.test(token);

/** The server's own client, or null where Webtools has no secret key (a local build). */
function serverClient() {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SECRET_KEY;
  if (!url || !key) return null;
  return createClient(url, key, {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
    global: { headers: { "X-Client-Info": "teamzone-webtools-server/0.1" } },
  });
}

async function read<T>(name: string, args: Record<string, string>): Promise<T | null> {
  const client = serverClient();
  if (!client) return null;
  const { data, error } = await client.schema("api").rpc(name, args);
  if (error) {
    console.error("shared tactics", name, error.message);
    return null;
  }
  return data as T | null;
}

const withBoards = (shared: SharedTactics | null) => shared && Array.isArray(shared.boards) && shared.boards.length > 0 ? shared : null;

export async function loadSharedTactics(token: string): Promise<SharedTactics | null> {
  if (!isToken(token)) return null;
  return withBoards(await read<SharedTactics>("get_shared_tactics", { target_token: token }));
}

export async function loadSharedFolder(token: string): Promise<SharedFolder | null> {
  if (!isToken(token)) return null;
  const folder = await read<SharedFolder>("get_shared_tactics_folder", { target_token: token });
  return folder && Array.isArray(folder.projects) ? folder : null;
}

/** One project of a shared folder; null unless it is in the folder. */
export async function loadSharedFolderProject(token: string, projectId: string): Promise<SharedTactics | null> {
  if (!isToken(token) || !/^[0-9a-f-]{36}$/.test(projectId)) return null;
  return withBoards(await read<SharedTactics>("get_shared_tactics_folder_project", { target_token: token, target_project_id: projectId }));
}
