"use client";

// TeamZone's library (decision package 13, step 2): searched with filters,
// an item fetched when it is used; sharing from your library, removing what
// you shared, and reporting.
import { useCallback, useState } from "react";
import type { Board } from "../../lib/tactics/model.ts";
import type { SharedFilters, SharedItemSummary } from "../../lib/tactics/library.ts";
import { useAccount } from "../account";

export function useSharedLibrary() {
  const { client, session } = useAccount();
  const [items, setItems] = useState<SharedItemSummary[] | null>(null);
  const [error, setError] = useState("");

  const search = useCallback(async (filters: SharedFilters) => {
    if (!client || !session) { setItems([]); return; }
    const { data, error: searchError } = await client.schema("api").rpc("search_tactics_shared_items", {
      search_text: filters.text.trim().slice(0, 100),
      item_kind: filters.kind || null, exercise_part: filters.part || null, game_phase: filters.phase || null,
      age_class: filters.age || null, game_form: filters.form || null, page: 0,
    });
    if (searchError) { setError("TeamZones bibliotek kunde inte hämtas."); setItems([]); return; }
    setError("");
    setItems(data as SharedItemSummary[]);
  }, [client, session]);

  /** An item's boards, or null when it could not be fetched. */
  const boardsOf = async (id: string): Promise<Board[] | null> => {
    if (!client) return null;
    const { data, error: loadError } = await client.schema("api").rpc("get_tactics_shared_item", { target_shared_id: id });
    if (loadError) { setError("Det kunde inte hämtas ur TeamZones bibliotek."); return null; }
    const boards = (data as { document: { boards?: Board[] } }).document.boards;
    return Array.isArray(boards) ? boards : null;
  };

  /** Shares an item of your library, or its latest version; true when done. */
  const share = async (libraryItemId: string) => {
    if (!client) return false;
    const { error: shareError } = await client.schema("api").rpc("share_tactics_library_item", { target_item_id: libraryItemId });
    if (shareError) {
      setError(shareError.message.includes("hidden_by_support")
        ? "TeamZones support har tagit bort den ur TeamZones bibliotek, så den kan inte delas igen."
        : shareError.message.includes("too_many_shared")
        ? "Du har redan delat 200 övningar, pass och sessioner."
        : "Det kunde inte delas i TeamZones bibliotek.");
      return false;
    }
    setError("");
    return true;
  };

  const unshare = async (sharedId: string) => {
    if (!client) return false;
    const { error: removeError } = await client.schema("api").rpc("unshare_tactics_item", { target_shared_id: sharedId });
    if (removeError) { setError("Det kunde inte tas bort ur TeamZones bibliotek."); return false; }
    setError("");
    return true;
  };

  const report = async (sharedId: string, reason: string) => {
    if (!client) return false;
    const { error: reportError } = await client.schema("api").rpc("report_tactics_shared_item", {
      target_shared_id: sharedId, report_reason: reason.trim().slice(0, 500),
    });
    if (reportError) { setError("Rapporten kunde inte skickas."); return false; }
    setError("");
    return true;
  };

  return { items, error, search, boardsOf, share, unshare, report };
}
