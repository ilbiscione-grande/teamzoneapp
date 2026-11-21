"use client";

// Either team shown or hidden, formations for either team, and the TeamZone
// team's squad: fetched into the project and put on the pitch one by one or
// by a formation.
import { useState } from "react";
import { applyFormation, createPlayer } from "../../../lib/tactics/document.ts";
import { formations, parseFormation } from "../../../lib/tactics/formations.ts";
import type { Board, Side, SquadPlayer } from "../../../lib/tactics/model.ts";
import { useAccount } from "../../account";
import { activeObjects, useEditor, NONE } from "../store.ts";
import { useSquadFetch } from "../use-squad.ts";
import { TeamVisibility } from "./TeamVisibility.tsx";
import { useT } from "../../language";
import { positionShort } from "../../../lib/tactics/player-label.ts";
import { linesOf } from "../../../lib/tactics/lineup.ts";
import { useTeamFormations, type FormationDraft } from "../use-team-formations.ts";
import { TeamLineup } from "./TeamLineup.tsx";

export function SquadPanel({ board }: { board: Board }) {
  const t = useT();
  const meta = useEditor(state => state.meta);
  const squad = useEditor(state => state.document?.squad ?? NONE);
  const objects = useEditor(activeObjects);
  const frameIndex = useEditor(state => state.frameIndex);
  const [side, setSide] = useState<Side>("home");
  const [formation, setFormation] = useState("4-3-3");
  const [custom, setCustom] = useState("");
  const { fetchSquad, busy, error } = useSquadFetch();
  const { changeObjects } = useEditor.getState();
  // The squad comes from a team in TeamZone; without one only the formations show.
  const hasTeams = (useAccount().connections?.length ?? 0) > 0;
  const placed = new Set(objects.flatMap(item => item.type === "player" && item.personId ? [item.personId] : []));

  // Players from other teams who may represent this one are listed apart and
  // put on the pitch by hand; a formation fills with the team's own.
  const own = squad.filter(player => player.homeTeam == null);
  const representatives = squad.filter(player => player.homeTeam != null);

  // The team's own formations, with what each place asks for, for its leaders.
  const team = useTeamFormations(meta?.teamId ?? null);
  const teamFormation = !custom.trim() && formation.startsWith("team:")
    ? team.formations.find(item => `team:${item.id}` === formation) ?? null : null;
  const lines = custom.trim() ? parseFormation(custom) : teamFormation ? linesOf(teamFormation.lines) : formations[formation] ?? null;
  const saveFormation = async (draft: FormationDraft) => {
    const saved = await team.save(draft);
    if (typeof saved === "string") return saved;
    setFormation(`team:${saved.id}`);
    setCustom("");
    return null;
  };
  const deleteFormation = async (formationId: string) => {
    if (await team.remove(formationId)) setFormation("4-3-3");
  };
  const place = () => {
    if (!lines) return;
    // The squad fills the home team; the away team is numbered.
    changeObjects(current => applyFormation(current, side, lines, side === "home" ? own : []));
  };


  const placeOne = (player: SquadPlayer) => {
    // A free spot just inside the own half, stepping down for each one placed.
    const index = objects.filter(item => item.type === "player" && item.side === "home").length;
    changeObjects(current => [...current, createPlayer({ x: 30 + (index % 4) * 4, y: 8 + Math.floor(index / 4) * 6 }, "home", current, player)]);
  };

  return (
    <div className="tb-inspector">
      <TeamVisibility board={board} frameIndex={frameIndex} />
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
            {team.formations.length > 0 ? (
              <>
                <optgroup label={t("Lagets formationer")}>
                  {team.formations.map(item => <option key={item.id} value={`team:${item.id}`}>{item.name}</option>)}
                </optgroup>
                <optgroup label={t("Vanliga formationer")}>
                  {Object.keys(formations).map(name => <option key={name} value={name}>{name}</option>)}
                </optgroup>
              </>
            ) : Object.keys(formations).map(name => <option key={name} value={name}>{name}</option>)}
          </select>
        </label>
      </div>
      <label className="tb-field">{t("Egen formation (frivilligt)")}<input value={custom} placeholder={t("T.ex. 3-1-4-2")} onChange={event => setCustom(event.target.value)} /></label>
      {custom.trim() && !lines && <p className="tb-hint">{t("Skriv raderna bakifrån, t.ex. 4-4-2, med 3–10 utespelare.")}</p>}
      <button type="button" className="wt-button small" disabled={!lines} onClick={place}>{t("Ställ upp laget")}</button>
      <p className="tb-hint">{t("Lagets spelare flyttas till formationen, och saknade läggs till.")}</p>
      {meta?.teamId && team.allowed && team.attributes && side === "home" && (
        <TeamLineup lines={lines} formation={teamFormation} presetName={custom.trim() || formation}
          attributes={team.attributes} squad={squad} onSave={saveFormation} onDelete={deleteFormation}
          suggest={choice => team.suggest(choice, null)} />
      )}

      {(meta?.teamId || hasTeams) && <h3>{t("Trupp")}</h3>}
      {!meta?.teamId ? (
        hasTeams && <p className="tb-hint">{t("Koppla projektet till ett av dina lag i TeamZone under Inställningar, så kan du hämta truppen.")}</p>
      ) : (
        <>
          <button type="button" className="wt-button secondary small" disabled={busy} onClick={() => void fetchSquad()}>
            {squad.length ? t("Hämta truppen igen") : t("Hämta truppen från {team}", { team: meta.teamName ?? t("laget") })}
          </button>
          {error && <p className="wt-error" role="alert">{error}</p>}
          {own.length > 0 && <SquadList players={own} placed={placed} onPlace={placeOne} />}
          {representatives.length > 0 && (
            <>
              <h4 className="tb-squad-heading">{t("Kan representera laget")}</h4>
              <SquadList players={representatives} placed={placed} onPlace={placeOne} />
            </>
          )}
        </>
      )}
    </div>
  );
}

function SquadList({ players, placed, onPlace }: { players: SquadPlayer[]; placed: Set<string>; onPlace: (player: SquadPlayer) => void }) {
  return (
    <ul className="tb-squad">
      {players.map(player => (
        <li key={player.personId}>
          <button type="button" disabled={placed.has(player.personId)} onClick={() => onPlace(player)}>
            <span className="tb-number">{player.number ?? "–"}</span>
            <span className="tb-squad-name">
              {player.name}
              {player.homeTeam && <small>{player.homeTeam}</small>}
            </span>
            {player.position && <span className="tb-position">{positionShort(player.position)}</span>}
          </button>
        </li>
      ))}
    </ul>
  );
}
