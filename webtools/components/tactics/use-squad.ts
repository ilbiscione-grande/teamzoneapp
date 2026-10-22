"use client";

// The project's TeamZone team's squad: fetched into the document (so the
// board keeps it when shared), and the home team named after the team.
import { useState } from "react";
import { updateBoard } from "../../lib/tactics/document.ts";
import type { SquadPlayer } from "../../lib/tactics/model.ts";
import { useAccount } from "../account";
import { useEditor } from "./store.ts";

export function useSquadFetch() {
  const { client } = useAccount();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  const fetchSquad = async () => {
    const { meta, change, boardId } = useEditor.getState();
    if (!client || !meta?.teamId) return;
    setBusy(true);
    setError("");
    const { data, error: loadError } = await client.schema("api").rpc("list_tactics_team_players", { target_team_id: meta.teamId });
    setBusy(false);
    if (loadError) { setError("Truppen kunde inte hämtas."); return; }
    const players: SquadPlayer[] = (data as { person_id: string; name: string; number: number | null; position: string | null }[])
      .map(player => ({ personId: player.person_id, name: player.name, number: player.number, position: player.position }));
    change(document => {
      const withSquad = { ...document, squad: players };
      if (!meta.teamName || !boardId) return withSquad;
      return updateBoard(withSquad, boardId, current => ({ ...current, teams: { ...current.teams, home: { ...current.teams.home, name: meta.teamName! } } }));
    });
  };

  return { fetchSquad, busy, error };
}
