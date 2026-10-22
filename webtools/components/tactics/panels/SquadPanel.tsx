"use client";

// Formations for either team, and the TeamZone team's squad: fetched into
// the project and put on the pitch one by one or by a formation.
import { useState } from "react";
import { applyFormation, createPlayer, updateBoard } from "../../../lib/tactics/document.ts";
import { formations, parseFormation } from "../../../lib/tactics/formations.ts";
import type { Board, Side, SquadPlayer } from "../../../lib/tactics/model.ts";
import { useAccount } from "../../account";
import { activeObjects, useEditor } from "../store.ts";

export function SquadPanel({ board }: { board: Board }) {
  const { client } = useAccount();
  const meta = useEditor(state => state.meta);
  const squad = useEditor(state => state.document?.squad ?? []);
  const objects = useEditor(activeObjects);
  const [side, setSide] = useState<Side>("home");
  const [formation, setFormation] = useState("4-3-3");
  const [custom, setCustom] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const { changeObjects, change } = useEditor.getState();
  const placed = new Set(objects.flatMap(item => item.type === "player" && item.personId ? [item.personId] : []));

  const lines = custom.trim() ? parseFormation(custom) : formations[formation];
  const place = () => {
    if (!lines) return;
    // The squad fills the home team; the away team is numbered.
    changeObjects(current => applyFormation(current, side, lines, side === "home" ? squad : []));
  };

  const fetchSquad = async () => {
    if (!client || !meta?.teamId) return;
    setBusy(true); setError("");
    const { data, error: loadError } = await client.schema("api").rpc("list_tactics_team_players", { target_team_id: meta.teamId });
    setBusy(false);
    if (loadError) { setError("Truppen kunde inte hämtas."); return; }
    const players = (data as { person_id: string; name: string; number: number | null; position: string | null }[])
      .map(player => ({ personId: player.person_id, name: player.name, number: player.number, position: player.position }));
    change(document => ({ ...document, squad: players }));
    if (meta.teamName) change(document => updateBoard(document, board.id, current => ({ ...current, teams: { ...current.teams, home: { ...current.teams.home, name: meta.teamName! } } })));
  };

  const placeOne = (player: SquadPlayer) => {
    // A free spot just inside the own half, stepping down for each one placed.
    const index = objects.filter(item => item.type === "player" && item.side === "home").length;
    changeObjects(current => [...current, createPlayer({ x: 30 + (index % 4) * 4, y: 8 + Math.floor(index / 4) * 6 }, "home", current, player)]);
  };

  return (
    <div className="tb-inspector">
      <h3>Formation</h3>
      <div className="tb-row">
        <label className="tb-field">Lag
          <select value={side} onChange={event => setSide(event.target.value as Side)}>
            <option value="home">{board.teams.home.name}</option>
            <option value="away">{board.teams.away.name}</option>
          </select>
        </label>
        <label className="tb-field">Formation
          <select value={formation} onChange={event => { setFormation(event.target.value); setCustom(""); }}>
            {Object.keys(formations).map(name => <option key={name} value={name}>{name}</option>)}
          </select>
        </label>
      </div>
      <label className="tb-field">Egen formation (frivilligt)<input value={custom} placeholder="T.ex. 3-1-4-2" onChange={event => setCustom(event.target.value)} /></label>
      {custom.trim() && !lines && <p className="tb-hint">Skriv raderna bakifrån, t.ex. 4-4-2, med 3–10 utespelare.</p>}
      <button type="button" className="wt-button small" disabled={!lines} onClick={place}>Ställ upp laget</button>
      <p className="tb-hint">Lagets spelare flyttas till formationen, och saknade läggs till.</p>

      <h3>Trupp</h3>
      {!meta?.teamId ? (
        <p className="tb-hint">Koppla projektet till ett av dina lag i TeamZone (under projektets namn) så kan du hämta truppen.</p>
      ) : (
        <>
          <button type="button" className="wt-button secondary small" disabled={busy} onClick={() => void fetchSquad()}>
            {squad.length ? "Hämta truppen igen" : `Hämta truppen från ${meta.teamName ?? "laget"}`}
          </button>
          {error && <p className="wt-error" role="alert">{error}</p>}
          {squad.length > 0 && (
            <ul className="tb-squad">
              {squad.map(player => (
                <li key={player.personId}>
                  <button type="button" disabled={placed.has(player.personId)} onClick={() => placeOne(player)}>
                    <span className="tb-number">{player.number ?? "–"}</span>
                    <span>{player.name}</span>
                    {player.position && <span className="tb-position">{player.position}</span>}
                  </button>
                </li>
              ))}
            </ul>
          )}
        </>
      )}
    </div>
  );
}
