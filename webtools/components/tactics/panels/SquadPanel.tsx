"use client";

// Either team shown or hidden, formations for either team, and the TeamZone
// team's squad: fetched into the project and put on the pitch one by one or
// by a formation.
import { useState } from "react";
import { applyFormation, createPlayer, updateBoard } from "../../../lib/tactics/document.ts";
import { formations, parseFormation } from "../../../lib/tactics/formations.ts";
import type { Board, Side, SquadPlayer } from "../../../lib/tactics/model.ts";
import { useAccount } from "../../account";
import { activeObjects, useEditor, NONE } from "../store.ts";
import { useSquadFetch } from "../use-squad.ts";
import { TeamVisibility } from "./TeamVisibility.tsx";
import { useLanguage } from "../../language";
import { positionShort } from "../../../lib/tactics/player-label.ts";
import { applySuggestion, byFormat, formatName, linesOf, matchFormat, type TeamFormation } from "../../../lib/tactics/lineup.ts";
import { useTeamFormations } from "../use-team-formations.ts";
import { FormationsDialog, type FormationUse } from "../formations/FormationsDialog.tsx";
import { TeamLineup, type SuggestionResult } from "./TeamLineup.tsx";

export function SquadPanel({ board }: { board: Board }) {
  const { t, locale } = useLanguage();
  const meta = useEditor(state => state.meta);
  const squad = useEditor(state => state.document?.squad ?? NONE);
  const objects = useEditor(activeObjects);
  const frameIndex = useEditor(state => state.frameIndex);
  const [side, setSide] = useState<Side>("home");
  const [custom, setCustom] = useState("");
  const [dialog, setDialog] = useState(false);
  const [suggesting, setSuggesting] = useState(false);
  const [suggestError, setSuggestError] = useState("");
  const [result, setResult] = useState<SuggestionResult | null>(null);
  const { fetchSquad, busy, error } = useSquadFetch();
  const { changeObjects } = useEditor.getState();
  // The squad comes from a team in TeamZone; without one only the formations show.
  const hasTeams = (useAccount().connections?.length ?? 0) > 0;
  const placed = new Set(objects.flatMap(item => item.type === "player" && item.personId ? [item.personId] : []));

  // Players from other teams who may represent this one are listed apart and
  // put on the pitch by hand; a formation fills with the team's own.
  const own = squad.filter(player => player.homeTeam == null);
  const representatives = squad.filter(player => player.homeTeam != null);

  // For the team's leaders the formations are the team's own and the
  // ready-made ones, with what each place asks for; else the presets. The
  // board keeps its choice.
  const team = useTeamFormations(meta?.teamId ?? null);
  const teamMode = !!meta?.teamId && team.allowed && !!team.attributes;
  const choices = [...team.formations, ...team.templates];
  const fallback = teamMode
    ? (team.templates.find(item => item.lines === "4-3-3" && item.match_format === "11v11") ?? choices[0])?.id ?? "4-3-3"
    : "4-3-3";
  const known = (value: string | undefined) => !!value && (teamMode ? choices.some(item => item.id === value) : value in formations);
  const formation = known(board.formation) ? board.formation! : fallback;
  const teamFormation = teamMode && !custom.trim() ? choices.find(item => item.id === formation) ?? null : null;
  const lines = custom.trim() ? parseFormation(custom) : teamFormation ? linesOf(teamFormation.lines) : formations[formation] ?? null;
  const choose = (value: string) => {
    setCustom("");
    setResult(null);
    const { change, boardId } = useEditor.getState();
    if (boardId) change(document => updateBoard(document, boardId, current => ({ ...current, formation: value })));
  };
  const place = (chosen = lines, onSide = side) => {
    if (!chosen) return;
    // The squad fills the home team; the away team is numbered.
    changeObjects(current => applyFormation(current, onSide, chosen, onSide === "home" ? own : []));
  };
  const suggest = async (chosen: TeamFormation | null, chosenLines: number[] | null) => {
    const format = chosenLines ? matchFormat(chosenLines) : null;
    if (!chosenLines || !format) return;
    setSuggesting(true);
    setSuggestError("");
    const suggestion = await team.suggest(chosen ? { formationId: chosen.id } : { lines: chosenLines.join("-"), matchFormat: format }, null);
    setSuggesting(false);
    if (!suggestion) { setSuggestError(t("Förslaget kunde inte hämtas.")); return; }
    setResult({ lines: chosenLines, suggestion });
    changeObjects(current => applySuggestion(current, "home", chosenLines, suggestion.slots, squad));
  };
  const applyChosen = (chosen: TeamFormation, how: FormationUse) => {
    setDialog(false);
    choose(chosen.id);
    setSide("home");
    if (how === "place") place(linesOf(chosen.lines), "home");
    else void suggest(chosen, linesOf(chosen.lines));
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
          <select value={formation} onChange={event => choose(event.target.value)}>
            {teamMode ? (
              <>
                {team.formations.length > 0 && (
                  <optgroup label={t("Lagets formationer")}>
                    {team.formations.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}
                  </optgroup>
                )}
                {byFormat(team.templates).map(([format, items]) => (
                  <optgroup key={format} label={t("Mallar · {format}", { format: formatName(format, locale === "en") })}>
                    {items.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}
                  </optgroup>
                ))}
              </>
            ) : Object.keys(formations).map(name => <option key={name} value={name}>{name}</option>)}
          </select>
        </label>
      </div>
      <label className="tb-field">{t("Egen formation (frivilligt)")}<input value={custom} placeholder={t("T.ex. 3-1-4-2")} onChange={event => setCustom(event.target.value)} /></label>
      {custom.trim() && !lines && <p className="tb-hint">{t("Skriv raderna bakifrån, t.ex. 4-4-2, med 3–10 utespelare.")}</p>}
      <button type="button" className="wt-button small" disabled={!lines} onClick={() => place()}>{t("Ställ upp laget")}</button>
      <p className="tb-hint">{t("Lagets spelare flyttas till formationen, och saknade läggs till.")}</p>
      {teamMode && side === "home" && (
        <TeamLineup formation={teamFormation} canSuggest={!!lines && !!matchFormat(lines)} busy={suggesting} error={suggestError}
          result={result} attributes={team.attributes!} onSuggest={() => void suggest(teamFormation, lines)} onOpen={() => setDialog(true)} />
      )}
      {dialog && team.attributes && (
        <FormationsDialog formations={team.formations} templates={team.templates} attributes={team.attributes}
          initial={teamFormation?.id ?? null} onSave={team.save} onDelete={team.remove} onUse={applyChosen} onClose={() => setDialog(false)} />
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
