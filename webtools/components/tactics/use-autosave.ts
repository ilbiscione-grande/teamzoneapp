"use client";

// Saves the project a moment after each change, whole, with the revision it
// was read at. A copy stays in the browser until the server has it, and a
// page left with unsaved changes asks first. Another tab's newer save is a
// conflict: nothing is overwritten.
import type { SupabaseClient } from "@supabase/supabase-js";
import { useEffect } from "react";
import { useEditor } from "./store.ts";

const DELAY_MS = 1200;
export const backupKey = (projectId: string) => `teamzone:tactics:${projectId}`;

export async function saveNow(client: SupabaseClient): Promise<void> {
  const { meta, document, setSaveState, saved } = useEditor.getState();
  if (!meta || !document) return;
  setSaveState("saving");
  const { data, error } = await client.schema("api").rpc("save_tactics_project", {
    target_project_id: meta.id, expected_revision: meta.revision, project_name: meta.name.trim() || "Namnlöst projekt",
    project_kind: meta.kind, target_team_id: meta.teamId, project_document: document,
  });
  if (error) {
    setSaveState(error.message.includes("stale_revision") ? "conflict" : "error");
    return;
  }
  saved(Number(data), document);
  try { localStorage.removeItem(backupKey(meta.id)); } catch { /* storage unavailable */ }
}

/** After a conflict: what is in hand as a project of your own, opened in place of this one. */
export async function saveAsCopy(client: SupabaseClient): Promise<boolean> {
  const { meta, document } = useEditor.getState();
  if (!meta || !document) return false;
  const { data, error } = await client.schema("api").rpc("create_tactics_project", {
    project_name: `${meta.name.trim() || "Namnlöst projekt"} (din kopia)`.slice(0, 120), project_kind: meta.kind,
    target_team_id: meta.teamId, project_document: document,
  });
  if (error) return false;
  try { localStorage.removeItem(backupKey(meta.id)); } catch { /* storage unavailable */ }
  window.location.href = `/tacticsboard/${(data as { id: string }).id}`;
  return true;
}

export function useAutosave(client: SupabaseClient | null) {
  const saveState = useEditor(state => state.saveState);
  const document = useEditor(state => state.document);
  const meta = useEditor(state => state.meta);

  useEffect(() => {
    if (!client || saveState !== "dirty" || !meta || !document) return;
    try {
      localStorage.setItem(backupKey(meta.id), JSON.stringify({ revision: meta.revision, document, savedAt: Date.now() }));
    } catch { /* storage unavailable or full: the server save still runs */ }
    const timer = window.setTimeout(() => void saveNow(client), DELAY_MS);
    return () => window.clearTimeout(timer);
  }, [client, saveState, document, meta]);

  useEffect(() => {
    const warn = (event: BeforeUnloadEvent) => {
      const state = useEditor.getState().saveState;
      if (state === "dirty" || state === "saving" || state === "error") event.preventDefault();
    };
    window.addEventListener("beforeunload", warn);
    return () => window.removeEventListener("beforeunload", warn);
  }, []);
}
