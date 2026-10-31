"use client";

// The new project's optional details in the dialog's last step: the phase
// of the game, age classes and game forms, as the library's filters know
// them. All may be left out.
import { ageClasses, ageClassLabels, gameFormLabels, gameForms, phaseLabels } from "../../../lib/tactics/library.ts";
import type { NewProjectDetails } from "../../../lib/tactics/home.ts";
import type { GamePhase } from "../../../lib/tactics/model.ts";

type Props = { value: NewProjectDetails; onChange: (value: NewProjectDetails) => void };

const toggle = <T,>(list: T[], item: T) => list.includes(item) ? list.filter(entry => entry !== item) : [...list, item];

/** The chosen details in words, for the dialog's summary; empty when none. */
export function detailsText(value: NewProjectDetails): string {
  return [
    value.phase && phaseLabels[value.phase],
    value.ageClasses.map(age => ageClassLabels[age]).join(", "),
    value.gameForms.map(form => gameFormLabels[form]).join(", "),
  ].filter(Boolean).join(" · ");
}

export function NewProjectDetailsFields({ value, onChange }: Props) {
  return (
    <section className="tb-new-details" aria-label="Inställningar för filtren">
      <h3>Inställningar för filtren <span>(valfritt)</span></h3>
      <p className="wt-small">Så hittar du projektet med filtren i ditt bibliotek. Inställningarna följer med till varje tavla och går att ändra på tavlan sedan.</p>
      <label>Skede
        <select value={value.phase} onChange={event => onChange({ ...value, phase: event.target.value as GamePhase | "" })}>
          <option value="">Inget valt</option>
          {Object.entries(phaseLabels).map(([key, label]) => <option key={key} value={key}>{label}</option>)}
        </select>
      </label>
      <fieldset className="tb-toggles">
        <legend>Ålder</legend>
        {ageClasses.map(age => (
          <button key={age} type="button" className="tb-chip" aria-pressed={value.ageClasses.includes(age)}
            onClick={() => onChange({ ...value, ageClasses: toggle(value.ageClasses, age) })}>{ageClassLabels[age]}</button>
        ))}
      </fieldset>
      <fieldset className="tb-toggles">
        <legend>Spelform</legend>
        {gameForms.map(form => (
          <button key={form} type="button" className="tb-chip" aria-pressed={value.gameForms.includes(form)}
            onClick={() => onChange({ ...value, gameForms: toggle(value.gameForms, form) })}>{gameFormLabels[form]}</button>
        ))}
      </fieldset>
    </section>
  );
}
