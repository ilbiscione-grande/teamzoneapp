"use client";

// What each place of a team formation asks for: a position, if any, and up to
// six attributes, each important or very important. Saved with the TeamZone
// team, so the app's line-up uses the same formation.
import { useState } from "react";
import { attributeOptions, type TeamAttributes } from "../../../lib/tactics/attributes.ts";
import { slotLabel, type FormationSlot, type Requirement } from "../../../lib/tactics/lineup.ts";
import { positionOptions } from "../../../lib/tactics/player-label.ts";
import { useLanguage } from "../../language";
import type { FormationDraft } from "../use-team-formations.ts";

const MAX_REQUIREMENTS = 6;

export function FormationRequirements({ draft, attributes, onSave, onDelete, onClose }: {
  draft: FormationDraft;
  attributes: TeamAttributes;
  onSave: (draft: FormationDraft) => Promise<string | null>;
  onDelete: (() => Promise<void>) | null;
  onClose: () => void;
}) {
  const { t, locale } = useLanguage();
  const [name, setName] = useState(draft.name);
  const [slots, setSlots] = useState<FormationSlot[]>(draft.slots);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const lines = draft.lines.split("-").map(Number);
  const options = attributeOptions(attributes, locale);
  const positions = positionOptions(attributes.sport, locale);
  const nameOf = (key: string) => options.find(option => option.key === key)?.name ?? key;

  const update = (code: string, change: (slot: FormationSlot) => FormationSlot) =>
    setSlots(current => current.map(slot => slot.code === code ? change(slot) : slot));
  const setRequirement = (code: string, requirement: Requirement | null, attribute: string) => update(code, slot => ({
    ...slot,
    requirements: requirement
      ? slot.requirements.some(item => item.attribute === attribute)
        ? slot.requirements.map(item => item.attribute === attribute ? requirement : item)
        : [...slot.requirements, requirement]
      : slot.requirements.filter(item => item.attribute !== attribute),
  }));

  const save = async () => {
    setBusy(true);
    setError("");
    const problem = await onSave({ ...draft, name: name.trim(), slots });
    setBusy(false);
    if (!problem) return;
    setError(problem === "formation_name_taken" ? t("Laget har redan en formation med det namnet.")
      : problem === "stale_revision" ? t("Någon annan har ändrat formationen. Stäng och öppna den igen.")
      : problem === "too_many_formations" ? t("Laget kan ha högst 30 formationer.")
      : t("Formationen kunde inte sparas."));
  };

  return (
    <section className="tb-requirements" aria-label={t("Krav per position")}>
      <h3>{t("Krav per position")}</h3>
      <p className="tb-hint">{t("Välj vad som är viktigt på varje plats. Sparas med laget i TeamZone och används av Föreslå spelare.")}</p>
      <label className="tb-field">{t("Namn")}<input value={name} maxLength={60} onChange={event => setName(event.target.value)} /></label>
      <ol className="tb-slots">
        {slots.map(slot => {
          const free = options.filter(option => !slot.requirements.some(item => item.attribute === option.key));
          return (
            <li key={slot.code}>
              <div className="tb-slot-head">
                <span className="tb-slot-code">{slotLabel(lines, slot.code, locale === "en")}</span>
                <select aria-label={t("Position")} value={slot.position ?? ""} onChange={event => update(slot.code, current => ({ ...current, position: event.target.value || null }))}>
                  <option value="">{t("Ingen särskild position")}</option>
                  {positions.map(position => <option key={position.key} value={position.key}>{position.name}</option>)}
                </select>
              </div>
              {slot.requirements.length > 0 && (
                <ul className="tb-requirement-list">
                  {slot.requirements.map(requirement => (
                    <li key={requirement.attribute}>
                      <span>{nameOf(requirement.attribute)}</span>
                      <button type="button" className={requirement.weight === 2 ? "is-very" : ""}
                        title={t("Växla mellan viktig och mycket viktig")}
                        onClick={() => setRequirement(slot.code, { attribute: requirement.attribute, weight: requirement.weight === 2 ? 1 : 2 }, requirement.attribute)}>
                        {requirement.weight === 2 ? t("Mycket viktig") : t("Viktig")}
                      </button>
                      <button type="button" className="tb-requirement-remove" aria-label={t("Ta bort {name}", { name: nameOf(requirement.attribute) })}
                        onClick={() => setRequirement(slot.code, null, requirement.attribute)}>×</button>
                    </li>
                  ))}
                </ul>
              )}
              {slot.requirements.length < MAX_REQUIREMENTS && (
                <select aria-label={t("Lägg till egenskap")} value="" onChange={event => event.target.value && setRequirement(slot.code, { attribute: event.target.value, weight: 1 }, event.target.value)}>
                  <option value="">{t("+ Lägg till egenskap")}</option>
                  {free.map(option => <option key={option.key} value={option.key}>{option.name}</option>)}
                </select>
              )}
            </li>
          );
        })}
      </ol>
      {error && <p className="wt-error" role="alert">{error}</p>}
      <div className="tb-requirements-actions">
        <button type="button" className="wt-button small" disabled={busy || !name.trim()} onClick={() => void save()}>{t("Spara formationen")}</button>
        <button type="button" className="wt-button secondary small" disabled={busy} onClick={onClose}>{t("Stäng")}</button>
        {onDelete && (
          <button type="button" className="wt-link-button" disabled={busy}
            onClick={() => { if (window.confirm(t("Ta bort formationen för hela laget?"))) void onDelete(); }}>{t("Ta bort formationen")}</button>
        )}
      </div>
    </section>
  );
}
