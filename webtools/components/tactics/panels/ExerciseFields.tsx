"use client";

// In a training project: the board as an exercise (decision package 13).
// The part of the session, minutes, players, area, coaching points, the
// phase of the game, and the age classes and game forms it suits. The
// organisation is the board's description. Saved with the project, and
// taken along when the board is saved in the library, or put in one of the
// team's coming training sessions.
import { useState } from "react";
import { updateBoard } from "../../../lib/tactics/document.ts";
import { ageClasses, ageClassLabels, emptyExercise, gameFormLabels, gameForms, partLabels, phaseLabels } from "../../../lib/tactics/library.ts";
import type { Board, ExerciseDetails, ExercisePart, GamePhase } from "../../../lib/tactics/model.ts";
import { useEditor } from "../store.ts";
import { TrainingLinkDialog } from "../TrainingLinkDialog.tsx";

export function ExerciseFields({ board }: { board: Board }) {
  const [linking, setLinking] = useState(false);
  const details = { ...emptyExercise, ...board.exercise };
  const change = (patch: Partial<ExerciseDetails>) => useEditor.getState().change(document =>
    updateBoard(document, board.id, current => ({ ...current, exercise: { ...emptyExercise, ...current.exercise, ...patch } })));
  const toggle = <T,>(list: T[], value: T, on: boolean) => on ? [...list.filter(item => item !== value), value] : list.filter(item => item !== value);
  return (
    <fieldset className="tb-team tb-exercise">
      <legend>Övningen</legend>
      <div className="tb-row">
        <label className="tb-field">Del av passet
          <select value={details.part} onChange={event => change({ part: event.target.value as ExercisePart })}>
            {Object.entries(partLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
          </select>
        </label>
        <label className="tb-field">Minuter
          <input type="number" min={0} max={240} value={details.minutes}
            onChange={event => change({ minutes: Math.max(0, Math.min(240, Number(event.target.value) || 0)) })} />
        </label>
      </div>
      <div className="tb-row">
        <label className="tb-field">Antal spelare
          <input type="number" min={1} max={60} value={details.players ?? ""} placeholder="Valfritt"
            onChange={event => change({ players: event.target.value === "" ? null : Math.max(1, Math.min(60, Number(event.target.value) || 1)) })} />
        </label>
        <label className="tb-field">Yta
          <input value={details.area} maxLength={40} placeholder="T.ex. 20x30 m" onChange={event => change({ area: event.target.value })} />
        </label>
      </div>
      <label className="tb-field">Skede i spelet
        <select value={details.phase ?? ""} onChange={event => change({ phase: (event.target.value || null) as GamePhase | null })}>
          <option value="">Inget skede</option>
          {Object.entries(phaseLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
        </select>
      </label>
      <label className="tb-field">Coachpunkter
        <textarea rows={3} maxLength={2000} value={details.coachingPoints} placeholder="Vad ledarna lyfter under övningen"
          onChange={event => change({ coachingPoints: event.target.value })} />
      </label>
      <p className="tb-hint">Organisationen skriver du under Beskrivning.</p>
      <div className="tb-field" role="group" aria-label="Åldersklasser">Åldersklasser
        <div className="tb-chips">
          {ageClasses.map(age => (
            <label key={age} className="tb-check">
              <input type="checkbox" checked={details.ageClasses.includes(age)}
                onChange={event => change({ ageClasses: toggle(details.ageClasses, age, event.target.checked) })} />
              {ageClassLabels[age]}
            </label>
          ))}
        </div>
      </div>
      <div className="tb-field" role="group" aria-label="Spelformer">Spelformer
        <div className="tb-chips">
          {gameForms.map(form => (
            <label key={form} className="tb-check">
              <input type="checkbox" checked={details.gameForms.includes(form)}
                onChange={event => change({ gameForms: toggle(details.gameForms, form, event.target.checked) })} />
              {gameFormLabels[form]}
            </label>
          ))}
        </div>
      </div>
      <button type="button" className="wt-button secondary small" onClick={() => setLinking(true)}>Lägg i ett träningspass…</button>
      {linking && <TrainingLinkDialog board={board} onClose={() => setLinking(false)} />}
    </fieldset>
  );
}
