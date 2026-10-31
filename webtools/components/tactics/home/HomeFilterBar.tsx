"use client";

// The start page's and the library's search: words, the kind as one tap,
// and the rest of the library's filters (part of the session, phase, age,
// game form) folded away until asked for.
import { useState } from "react";
import { ageClasses, ageClassLabels, gameFormLabels, gameForms, partLabels, phaseLabels } from "../../../lib/tactics/library.ts";
import type { AgeClass, ExercisePart, GameForm, GamePhase } from "../../../lib/tactics/model.ts";

type Filters = { text: string; kind: string; part: ExercisePart | ""; phase: GamePhase | ""; age: AgeClass | ""; form: GameForm | "" };
type Props<F extends Filters> = { filters: F; onChange: (filters: F) => void; kinds: Record<string, string>; placeholder?: string };

export function HomeFilterBar<F extends Filters>({ filters, onChange, kinds, placeholder = "Sök på namn, tavlor, beskrivning" }: Props<F>) {
  const more = [filters.part, filters.phase, filters.age, filters.form].filter(Boolean).length;
  const [open, setOpen] = useState(more > 0);
  const set = (patch: Partial<Filters>) => onChange({ ...filters, ...patch });
  const select = (label: string, key: "part" | "phase" | "age" | "form", options: [string, string][]) => (
    <label>{label}
      <select value={filters[key]} onChange={event => set({ [key]: event.target.value } as Partial<Filters>)}>
        <option value="">Alla</option>
        {options.map(([value, text]) => <option key={value} value={value}>{text}</option>)}
      </select>
    </label>
  );
  return (
    <div className="tb-filterbar">
      <div className="tb-filterbar-row">
        <label className="tb-search">
          <span className="tb-sr-only">Sök bland projekten</span>
          <svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="6.5" /><path d="m16 16 4.5 4.5" /></svg>
          <input type="search" value={filters.text} maxLength={100} placeholder={placeholder}
            onChange={event => set({ text: event.target.value })} />
        </label>
        <div className="tb-segments" role="group" aria-label="Typ">
          {[["", "Alla"], ...Object.entries(kinds)].map(([value, label]) => (
            <button key={value || "all"} type="button" aria-pressed={filters.kind === value} onClick={() => set({ kind: value })}>{label}</button>
          ))}
        </div>
        <button type="button" className="wt-button secondary small" aria-expanded={open} onClick={() => setOpen(!open)}>
          Fler filter{more > 0 ? ` (${more})` : ""}
        </button>
      </div>
      {open && (
        <div className="bk-times tb-filters wt-form">
          {select("Del av passet", "part", Object.entries(partLabels))}
          {select("Skede", "phase", Object.entries(phaseLabels))}
          {select("Ålder", "age", ageClasses.map(age => [age, ageClassLabels[age]]))}
          {select("Spelform", "form", gameForms.map(form => [form, gameFormLabels[form]]))}
          {more > 0 && (
            <button type="button" className="wt-link tb-inline-button" onClick={() => set({ part: "", phase: "", age: "", form: "" })}>
              Rensa filtren
            </button>
          )}
        </div>
      )}
    </div>
  );
}
