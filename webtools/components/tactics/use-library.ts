"use client";

// Your library (decision package 13): listed with each item's details, a
// whole item fetched when it is used. Saving the same board or project
// again updates its entry.
import { useCallback, useEffect, useState } from "react";
import type { Board } from "../../lib/tactics/model.ts";
import type { LibraryItemSummary, LibrarySave } from "../../lib/tactics/library.ts";
import { useAccount } from "../account";

export function useLibrary(enabled = true) {
  const { client, session } = useAccount();
  const [items, setItems] = useState<LibraryItemSummary[] | null>(null);
  const [error, setError] = useState("");

  const reload = useCallback(async () => {
    // Signed out (the demo board) there are none.
    if (!client || !session) { setItems([]); return; }
    const { data, error: loadError } = await client.schema("api").rpc("list_my_tactics_library");
    if (loadError) { setError("Biblioteket kunde inte hämtas."); setItems([]); return; }
    setError("");
    setItems(data as LibraryItemSummary[]);
  }, [client, session]);
  useEffect(() => { if (enabled) void reload(); }, [enabled, reload]);

  /** An item's boards, or null when it could not be fetched. */
  const boardsOf = async (id: string): Promise<Board[] | null> => {
    if (!client) return null;
    const { data, error: loadError } = await client.schema("api").rpc("get_tactics_library_item", { target_item_id: id });
    if (loadError) { setError("Övningen kunde inte hämtas."); return null; }
    const boards = (data as { document: { boards?: Board[] } }).document.boards;
    return Array.isArray(boards) ? boards : null;
  };

  /** Saves the item; the entry as saved, or null. */
  const save = async (item: LibrarySave, projectId: string | null, boardId: string | null) => {
    if (!client) return null;
    const { data, error: saveError } = await client.schema("api").rpc("save_tactics_library_item", {
      item_kind: item.kind, item_title: item.title, item_details: item.details, item_document: item.document,
      from_project_id: projectId, from_board_id: boardId,
    });
    if (saveError) {
      setError(saveError.message.includes("too_many_items")
        ? "Ditt bibliotek har redan 500 övningar, pass och sessioner. Ta bort något först."
        : "Det kunde inte sparas i biblioteket.");
      return null;
    }
    void reload();
    return data as LibraryItemSummary & { created: boolean };
  };

  const remove = async (id: string) => {
    if (!client) return;
    const { error: removeError } = await client.schema("api").rpc("delete_tactics_library_item", { target_item_id: id });
    if (removeError) { setError("Det kunde inte tas bort ur biblioteket."); return; }
    void reload();
  };

  return { items, error, reload, boardsOf, save, remove, signedIn: !!session };
}
