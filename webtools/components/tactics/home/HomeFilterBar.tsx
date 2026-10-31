"use client";

// The start page's search: words, the kind as one tap, and the rest of the
// library's filters (part of the session, phase, age, game form) folded
// away until asked for.
import { useState } from "react";
import { ageClasses, ageClassLabels, gameFormLabels, gameForms, partLabels, phaseLabels } from "../../../lib/tactics/library.ts";
import type { ProjectKind } from "../../../lib/tactics/model.ts";
import { kindLabels } from "../TopBar.tsx";
import { noHomeFilters, type HomeFilters } from "./use-home-projects.ts";

export function HomeFilterBar({ filters, onChange }: { filters: HomeFilters; onChange: (filters: HomeFilters) => void }) {
  const more = [filters.part, filters.phase, filters.age, filters.form].filter(Boolean).length;
  const [open, setOpen] = useState(more > 0);
  const set = (patch: Partial<HomeFilters>) => onChange({ ...filters, ...patch });
  const select = (label: string, key: "part" | "phase" | "age" | "form", options: [string, string][]) => (
    <label>{label}
      <select value={filters[key]} onChange={event => set({ [key]: event.target.value } as Partial<HomeFilters>)}>
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
          <input type="search" value={filters.text} maxLength={100} placeholder="Sök på namn, tavlor, beskrivning"
            onChange={event => set({ text: event.target.value })} />
        </label>
        <div className="tb-segments" role="group" aria-label="Typ">
          {([["", "Alla"], ...Object.entries(kindLabels)] as [ProjectKind | "", string][]).map(([value, label]) => (
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
            <button type="button" className="wt-link tb-inline-button" onClick={() => onChange({ ...noHomeFilters, text: filters.text, kind: filters.kind })}>
              Rensa filtren
            </button>
          )}
        </div>
      )}
    </div>
  );
}
