"use client";

// What one place of a formation asks for: a position, if any, and up to six
// attributes, each important or very important. Read-only for a template.
import { attributeOptions, type TeamAttributes } from "../../../lib/tactics/attributes.ts";
import { slotLabel, type FormationSlot, type Requirement } from "../../../lib/tactics/lineup.ts";
import { positionName, positionOptions } from "../../../lib/tactics/player-label.ts";
import { useLanguage } from "../../language";

const MAX_REQUIREMENTS = 6;

export function SlotEditor({ slot, lines, attributes, readOnly, onChange }: {
  slot: FormationSlot;
  lines: number[];
  attributes: TeamAttributes;
  readOnly: boolean;
  onChange: (slot: FormationSlot) => void;
}) {
  const { t, locale } = useLanguage();
  const options = attributeOptions(attributes, locale);
  const positions = positionOptions(attributes.sport, locale);
  const nameOf = (key: string) => options.find(option => option.key === key)?.name ?? key;
  const free = options.filter(option => !slot.requirements.some(item => item.attribute === option.key));
  const setRequirement = (attribute: string, requirement: Requirement | null) => onChange({
    ...slot,
    requirements: requirement
      ? slot.requirements.some(item => item.attribute === attribute)
        ? slot.requirements.map(item => item.attribute === attribute ? requirement : item)
        : [...slot.requirements, requirement]
      : slot.requirements.filter(item => item.attribute !== attribute),
  });

  return (
    <div className="tb-slot-editor">
      <h3>
        <span className="tb-slot-code">{slotLabel(lines, slot.code, locale === "en")}</span>
        {slot.position ? positionName(slot.position, locale) : t("Ingen särskild position")}
      </h3>
      {!readOnly && (
        <label className="tb-field">{t("Position")}
          <select value={slot.position ?? ""} onChange={event => onChange({ ...slot, position: event.target.value || null })}>
            <option value="">{t("Ingen särskild position")}</option>
            {positions.map(position => <option key={position.key} value={position.key}>{position.name}</option>)}
          </select>
        </label>
      )}
      <h4>{t("Viktiga egenskaper")}</h4>
      {slot.requirements.length === 0 ? <p className="tb-hint">{t("Inga ännu. Platsen går då bara efter position.")}</p> : (
        <ul className="tb-requirement-list">
          {slot.requirements.map(requirement => (
            <li key={requirement.attribute}>
              <span>{nameOf(requirement.attribute)}</span>
              {readOnly ? (
                <span className={`tb-requirement-weight${requirement.weight === 2 ? " is-very" : ""}`}>
                  {requirement.weight === 2 ? t("Mycket viktig") : t("Viktig")}
                </span>
              ) : (
                <>
                  <button type="button" className={requirement.weight === 2 ? "is-very" : ""} title={t("Växla mellan viktig och mycket viktig")}
                    onClick={() => setRequirement(requirement.attribute, { attribute: requirement.attribute, weight: requirement.weight === 2 ? 1 : 2 })}>
                    {requirement.weight === 2 ? t("Mycket viktig") : t("Viktig")}
                  </button>
                  <button type="button" className="tb-requirement-remove" aria-label={t("Ta bort {name}", { name: nameOf(requirement.attribute) })}
                    onClick={() => setRequirement(requirement.attribute, null)}>×</button>
                </>
              )}
            </li>
          ))}
        </ul>
      )}
      {!readOnly && slot.requirements.length < MAX_REQUIREMENTS && (
        <select className="tb-requirement-add" aria-label={t("Lägg till egenskap")} value=""
          onChange={event => event.target.value && setRequirement(event.target.value, { attribute: event.target.value, weight: 1 })}>
          <option value="">{t("+ Lägg till egenskap")}</option>
          {free.map(option => <option key={option.key} value={option.key}>{option.name}</option>)}
        </select>
      )}
    </div>
  );
}
