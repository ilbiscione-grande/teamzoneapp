"use client";

// Formations for either team, and the TeamZone team's squad: fetched into
// the project and put on the pitch one by one or by a formation.
import { useState } from "react";
import { applyFormation, createPlayer } from "../../../lib/tactics/document.ts";
import { formations, parseFormation } from "../../../lib/tactics/formations.ts";
import type { Board, Side, SquadPlayer } from "../../../lib/tactics/model.ts";
import { useAccount } from "../../account";
import { activeObjects, useEditor, NONE } from "../store.ts";
import { useSquadFetch } from "../use-squad.ts";
import { useT } from "../../language";

export function SquadPanel({ board }: { board: Board }) {
  const t = useT();
  const meta = useEditor(state => state.meta);
  const squad = useEditor(state => state.document?.squad ?? NONE);
  const objects = useEditor(activeObjects);
  const [side, setSide] = useState<Side>("home");
  const [formation, setFormation] = useState("4-3-3");
  const [custom, setCustom] = useState("");
  const { fetchSquad, busy, error } = useSquadFetch();
  const { changeObjects } = useEditor.getState();
  // The squad comes from a team in TeamZone; without one only the formations show.
  const hasTeams = (useAccount().connections?.length ?? 0) > 0;
  const placed = new Set(objects.flatMap(item => item.type === "player" && item.personId ? [item.personId] : []));

  const lines = custom.trim() ? parseFormation(custom) : formations[formation];
  const place = () => {
    if (!lines) return;
    // The squad fills the home team; the away team is numbered.
    changeObjects(current => applyFormation(current, side, lines, side === "home" ? squad : []));
  };


  const placeOne = (player: SquadPlayer) => {
    // A free spot just inside the own half, stepping down for each one placed.
    const index = objects.filter(item => item.type === "player" && item.side === "home").length;
    changeObjects(current => [...current, createPlayer({ x: 30 + (index % 4) * 4, y: 8 + Math.floor(index / 4) * 6 }, "home", current, player)]);
  };

  return (
    <div className="tb-inspector">
      <h3>{t("Formation")}</h3>
      <div className="tb-row">
        <label className="tb-field">{t("Lag")}
          <select value={side} onChange={event => setSide(event.target.value as Side)}>
            <option value="home">{t(board.teams.home.name)}</option>
            <option value="away">{t(board.teams.away.name)}</option>
          </select>
        </label>
        <label className="tb-field">{t("Formation")}
          <select value={formation} onChange={event => { setFormation(event.target.value); setCustom(""); }}>
            {Object.keys(formations).map(name => <option key={name} value={name}>{name}</option>)}
          </select>
        </label>
      </div>
      <label className="tb-field">{t("Egen formation (frivilligt)")}<input value={custom} placeholder={t("T.ex. 3-1-4-2")} onChange={event => setCustom(event.target.value)} /></label>
      {custom.trim() && !lines && <p className="tb-hint">{t("Skriv raderna bakifrån, t.ex. 4-4-2, med 3–10 utespelare.")}</p>}
      <button type="button" className="wt-button small" disabled={!lines} onClick={place}>{t("Ställ upp laget")}</button>
      <p className="tb-hint">{t("Lagets spelare flyttas till formationen, och saknade läggs till.")}</p>

      {(meta?.teamId || hasTeams) && <h3>{t("Trupp")}</h3>}
      {!meta?.teamId ? (
        hasTeams && <p className="tb-hint">{t("Koppla projektet till ett av dina lag i TeamZone under Inställningar, så kan du hämta truppen.")}</p>
      ) : (
        <>
          <button type="button" className="wt-button secondary small" disabled={busy} onClick={() => void fetchSquad()}>
            {squad.length ? t("Hämta truppen igen") : t("Hämta truppen från {team}", { team: meta.teamName ?? t("laget") })}
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
