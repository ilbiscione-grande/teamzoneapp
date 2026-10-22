"use client";

// A player on the pitch tied to a player of the TeamZone team: the name,
// shirt number and position are copied from the squad when tied, and what is
// written by hand afterwards wins; fetching the squad again leaves it be.
// Untied, the player keeps what it shows.
import type { PlayerObject } from "../../../lib/tactics/model.ts";
import { activeObjects, useEditor, NONE } from "../store.ts";
import { useSquadFetch } from "../use-squad.ts";

export function PlayerLink({ item }: { item: PlayerObject }) {
  const meta = useEditor(state => state.meta);
  const squad = useEditor(state => state.document?.squad ?? NONE);
  const objects = useEditor(activeObjects);
  const { fetchSquad, busy, error } = useSquadFetch();
  const placed = new Set(objects.flatMap(other => other.type === "player" && other.personId && other.id !== item.id ? [other.personId] : []));

  if (squad.length === 0) {
    if (!meta?.teamId) return null;
    return (
      <div className="tb-field">
        <span>Spelare i laget</span>
        <button type="button" className="wt-button secondary small" disabled={busy} onClick={() => void fetchSquad()}>
          Hämta truppen från {meta.teamName ?? "laget"}
        </button>
        {error && <span className="wt-error" role="alert">{error}</span>}
      </div>
    );
  }
  const choose = (personId: string) => {
    const player = squad.find(entry => entry.personId === personId);
    // Untying keeps the name, number and position on the pitch, to change by hand.
    const changes: Partial<PlayerObject> = player
      ? { personId: player.personId, name: player.name, ...(player.number !== null ? { number: player.number } : {}), ...(player.position ? { position: player.position } : {}) }
      : { personId: null };
    useEditor.getState().patch({ [item.id]: changes });
  };
  return (
    <label className="tb-field">Spelare i laget
      <select value={item.personId ?? ""} onChange={event => choose(event.target.value)}>
        <option value="">Ingen koppling</option>
        {squad.map(player => (
          <option key={player.personId} value={player.personId}>
            {[player.number !== null ? `#${player.number}` : null, player.name, player.position, placed.has(player.personId) ? "(på planen)" : null].filter(Boolean).join(" · ")}
          </option>
        ))}
      </select>
    </label>
  );
}
