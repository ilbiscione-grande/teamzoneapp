"use client";

// The library (decision package 13): searched with filters, the whole of
// it or a club's list; an item fetched when it is used; sharing from your
// library with the community or a club, removing, reporting, and picking
// items for a club's list.
import { useCallback, useEffect, useState } from "react";
import type { Board } from "../../lib/tactics/model.ts";
import type { SharedFilters, SharedItemSummary, TacticsClub } from "../../lib/tactics/library.ts";
import { useAccount } from "../account";

export function useSharedLibrary() {
  const { client, session } = useAccount();
  const [items, setItems] = useState<SharedItemSummary[] | null>(null);
  const [error, setError] = useState("");
  const [clubs, setClubs] = useState<TacticsClub[]>([]);

  useEffect(() => {
    if (!client || !session) { setClubs([]); return; }
    void client.schema("api").rpc("list_my_tactics_clubs").then(({ data }) => setClubs((data as TacticsClub[] | null) ?? []));
  }, [client, session]);

  /** The whole library you see, with [clubId] that club's list, or only your favourites. */
  const search = useCallback(async (filters: SharedFilters, clubId: string | null = null, onlyFavorites = false) => {
    if (!client || !session) { setItems([]); return; }
    const { data, error: searchError } = await client.schema("api").rpc("search_tactics_shared_items", {
      search_text: filters.text.trim().slice(0, 100),
      item_kind: filters.kind || null, exercise_part: filters.part || null, game_phase: filters.phase || null,
      age_class: filters.age || null, game_form: filters.form || null, target_club_id: clubId, only_favorites: onlyFavorites, page: 0,
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

  /** Shares an item of your library with the community (null) or one club, or its latest version; true when done. */
  const share = async (libraryItemId: string, clubId: string | null) => {
    if (!client) return false;
    const { error: shareError } = await client.schema("api").rpc("share_tactics_library_item", {
      target_item_id: libraryItemId, target_club_id: clubId,
    });
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

  /** Puts an item in a club's list, or takes it out; for those who keep the list. */
  const pick = async (clubId: string, sharedId: string, picked: boolean) => {
    if (!client) return false;
    const { error: pickError } = await client.schema("api").rpc("set_tactics_club_pick", {
      target_club_id: clubId, target_shared_id: sharedId, picked,
    });
    if (pickError) { setError("Klubbens lista kunde inte ändras."); return false; }
    setError("");
    return true;
  };

  /** Marks an item as a favourite, or unmarks it. */
  const favorite = async (sharedId: string, marked: boolean) => {
    if (!client) return false;
    const { error: markError } = await client.schema("api").rpc("set_tactics_favorite", { target_shared_id: sharedId, marked });
    if (markError) {
      setError(markError.message.includes("too_many_favorites") ? "Du har redan 500 favoriter." : "Favoriten kunde inte sparas.");
      return false;
    }
    setError("");
    return true;
  };

  return { items, error, clubs, search, boardsOf, share, unshare, report, pick, favorite };
}
