"use client";

// Your saved templates: listed by name with their boards' names, a whole
// template fetched when it is used.
import { useCallback, useEffect, useState } from "react";
import type { Board, ProjectKind } from "../../lib/tactics/model.ts";
import type { TemplateSummary } from "../../lib/tactics/templates.ts";
import { useAccount } from "../account";

export function useTemplates(enabled = true) {
  const { client } = useAccount();
  const [templates, setTemplates] = useState<TemplateSummary[] | null>(null);
  const [error, setError] = useState("");

  const reload = useCallback(async () => {
    // Signed out (the demo board) there are none.
    if (!client) { setTemplates([]); return; }
    const { data, error: loadError } = await client.schema("api").rpc("list_my_tactics_templates");
    if (loadError) { setError("Mallarna kunde inte hämtas."); setTemplates([]); return; }
    setError("");
    setTemplates(data as TemplateSummary[]);
  }, [client]);
  useEffect(() => { if (enabled) void reload(); }, [enabled, reload]);

  /** A template's boards, or null when it could not be fetched. */
  const boardsOf = async (id: string): Promise<Board[] | null> => {
    if (!client) return null;
    const { data, error: loadError } = await client.schema("api").rpc("get_tactics_template", { target_template_id: id });
    if (loadError) { setError("Mallen kunde inte hämtas."); return null; }
    const boards = (data as { document: { boards?: Board[] } }).document.boards;
    return Array.isArray(boards) ? boards : null;
  };

  const save = async (name: string, kind: ProjectKind, boards: Board[]) => {
    if (!client) return false;
    const { error: saveError } = await client.schema("api").rpc("save_tactics_template", {
      template_name: name, template_kind: kind, template_document: { schemaVersion: 1, boards },
    });
    if (saveError) {
      setError(saveError.message.includes("too_many_templates") ? "Du har redan 100 mallar. Ta bort någon först." : "Mallen kunde inte sparas.");
      return false;
    }
    void reload();
    return true;
  };

  const remove = async (id: string) => {
    if (!client) return;
    const { error: removeError } = await client.schema("api").rpc("delete_tactics_template", { target_template_id: id });
    if (removeError) { setError("Mallen kunde inte tas bort."); return; }
    void reload();
  };

  return { templates, error, reload, boardsOf, save, remove };
}
