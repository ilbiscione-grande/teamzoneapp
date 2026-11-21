"use client";

// What one place of a formation asks for: a position, a foot, and up to six
// attributes, each important or very important. Read-only for a template.
// An attribute's name opens what it means and where it matters most.
import { useState } from "react";
import { attributeHelp, attributeOptions, type TeamAttributes } from "../../../lib/tactics/attributes.ts";
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
  const [helpFor, setHelpFor] = useState<string | null>(null);
  const options = attributeOptions(attributes, locale);
  const positions = positionOptions(attributes.sport, locale);
  const nameOf = (key: string) => options.find(option => option.key === key)?.name ?? key;
  const free = options.filter(option => !slot.requirements.some(item => item.attribute === option.key));
  const help = helpFor ? attributeHelp(helpFor, attributes, locale) : null;
  const footName = (foot: FormationSlot["foot"]) => foot === "left" ? t("Vänsterfotad") : foot === "right" ? t("Högerfotad") : t("Spelar ingen roll");
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
      {readOnly ? (
        slot.foot && <p className="tb-hint">{t("Fot")}: {footName(slot.foot)}</p>
      ) : (
        <div className="tb-row">
          <label className="tb-field">{t("Position")}
            <select value={slot.position ?? ""} onChange={event => onChange({ ...slot, position: event.target.value || null })}>
              <option value="">{t("Ingen särskild position")}</option>
              {positions.map(position => <option key={position.key} value={position.key}>{position.name}</option>)}
            </select>
          </label>
          <label className="tb-field">{t("Fot")}
            <select value={slot.foot ?? ""} onChange={event => onChange({ ...slot, foot: (event.target.value || null) as FormationSlot["foot"] })}>
              <option value="">{footName(null)}</option>
              <option value="left">{footName("left")}</option>
              <option value="right">{footName("right")}</option>
            </select>
          </label>
        </div>
      )}
      <h4>{t("Viktiga egenskaper")}</h4>
      {slot.requirements.length === 0 ? <p className="tb-hint">{t("Inga ännu. Platsen går då bara efter position.")}</p> : (
        <ul className="tb-requirement-list">
          {slot.requirements.map(requirement => (
            <li key={requirement.attribute}>
              <button type="button" className="tb-requirement-name" aria-expanded={helpFor === requirement.attribute}
                title={attributeHelp(requirement.attribute, attributes, locale)?.about}
                onClick={() => setHelpFor(current => current === requirement.attribute ? null : requirement.attribute)}>
                {nameOf(requirement.attribute)}{attributeHelp(requirement.attribute, attributes, locale) && <span aria-hidden="true"> ⓘ</span>}
              </button>
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
      {help && helpFor && (
        <div className="tb-attribute-help" role="note">
          <strong>{nameOf(helpFor)}</strong>
          <p>{help.about}</p>
          {help.positions.length > 0 && (
            <p className="tb-hint">{t("Viktigast för")}: {help.positions.map(position => positionName(position, locale)).join(", ")}</p>
          )}
        </div>
      )}
      {!readOnly && slot.requirements.length < MAX_REQUIREMENTS && (
        <select className="tb-requirement-add" aria-label={t("Lägg till egenskap")} value=""
          onChange={event => { if (!event.target.value) return; setRequirement(event.target.value, { attribute: event.target.value, weight: 1 }); setHelpFor(event.target.value); }}>
          <option value="">{t("+ Lägg till egenskap")}</option>
          {free.map(option => <option key={option.key} value={option.key} title={attributeHelp(option.key, attributes, locale)?.about}>{option.name}</option>)}
        </select>
      )}
    </div>
  );
}
