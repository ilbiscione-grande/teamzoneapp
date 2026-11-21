"use client";

// For a project linked to a TeamZone team, its leaders' tools under the
// formation: suggest who plays where (by position and the attributes each
// place asks for) and set what the places ask for.
import { useState } from "react";
import { attributeName, type TeamAttributes } from "../../../lib/tactics/attributes.ts";
import { applySuggestion, formationSlots, matchFormat, slotLabel, type Suggestion, type TeamFormation } from "../../../lib/tactics/lineup.ts";
import type { SquadPlayer } from "../../../lib/tactics/model.ts";
import { useLanguage } from "../../language";
import { useEditor } from "../store.ts";
import type { FormationDraft } from "../use-team-formations.ts";
import { FormationRequirements } from "./FormationRequirements.tsx";

export function TeamLineup({ lines, formation, presetName, attributes, squad, onSave, onDelete, suggest }: {
  lines: number[] | null;
  /** The chosen team formation; null when a preset or a typed formation is chosen. */
  formation: TeamFormation | null;
  presetName: string;
  attributes: TeamAttributes;
  squad: SquadPlayer[];
  onSave: (draft: FormationDraft) => Promise<string | null>;
  onDelete: (formationId: string) => Promise<void>;
  suggest: (choice: { formationId: string } | { lines: string; matchFormat: string }) => Promise<Suggestion | null>;
}) {
  const { t, locale } = useLanguage();
  const [editing, setEditing] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [result, setResult] = useState<{ lines: number[]; suggestion: Suggestion } | null>(null);
  const format = lines ? matchFormat(lines) : null;

  if (!lines) return null;
  if (!format) return <p className="tb-hint">{t("Förslag och krav finns för 5, 7, 9 och 11 spelare.")}</p>;

  const suggestNow = async () => {
    setBusy(true);
    setError("");
    const suggestion = await suggest(formation ? { formationId: formation.id } : { lines: lines.join("-"), matchFormat: format });
    setBusy(false);
    if (!suggestion) { setError(t("Förslaget kunde inte hämtas.")); return; }
    setResult({ lines, suggestion });
    useEditor.getState().changeObjects(current => applySuggestion(current, "home", lines, suggestion.slots, squad));
  };

  const draft: FormationDraft = formation
    ? { id: formation.id, name: formation.name, lines: formation.lines, matchFormat: formation.match_format, slots: formation.slots, revision: formation.revision }
    : { id: null, name: presetName, lines: lines.join("-"), matchFormat: format, revision: null,
      slots: formationSlots(lines).map(slot => ({ ...slot, position: null, requirements: [] })) };

  const why = (slot: Suggestion["slots"][number]) => [
    slot.position_fit === "main" ? t("Huvudposition") : slot.position_fit === "other" ? t("Kan positionen") : slot.position_fit === "group" ? t("Rätt lagdel") : null,
    ...(slot.strengths ?? []).map(key => "+ " + attributeName(key, attributes, locale)),
    ...(slot.development ?? []).map(key => "− " + attributeName(key, attributes, locale)),
  ].filter(Boolean).join(" · ");

  return (
    <div className="tb-team-lineup">
      <div className="tb-requirements-actions">
        <button type="button" className="wt-button small" disabled={busy} onClick={() => void suggestNow()}>{t("Föreslå spelare")}</button>
        <button type="button" className="wt-button secondary small" onClick={() => setEditing(open => !open)} aria-expanded={editing}>{t("Krav per position")}</button>
      </div>
      <p className="tb-hint">{formation
        ? t("Hemmalaget ställs upp efter position och de egenskaper varje plats kräver.")
        : t("Hemmalaget ställs upp efter position. Lägg till krav per position för att väga in egenskaper.")}</p>
      {error && <p className="wt-error" role="alert">{error}</p>}
      {result && (
        <ol className="tb-suggestion" aria-label={t("Förslaget")}>
          {result.suggestion.slots.map(slot => (
            <li key={slot.code}>
              <span className="tb-slot-code">{slotLabel(result.lines, slot.code, locale === "en")}</span>
              <span className="tb-squad-name">
                {slot.name ?? t("Ingen spelare")}
                {slot.person_id && <small>{why(slot)}</small>}
              </span>
            </li>
          ))}
        </ol>
      )}
      {editing && (
        <FormationRequirements key={`${draft.id ?? draft.lines}-${draft.revision ?? 0}`} draft={draft} attributes={attributes}
          onSave={async next => { const problem = await onSave(next); if (!problem) setEditing(false); return problem; }}
          onDelete={formation ? async () => { await onDelete(formation.id); setEditing(false); } : null}
          onClose={() => setEditing(false)} />
      )}
    </div>
  );
}
