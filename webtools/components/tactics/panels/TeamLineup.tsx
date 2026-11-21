"use client";

// For a project linked to a TeamZone team, its leaders' tools under the
// formation: suggest who plays where (by position and what each place of the
// formation asks for), open the formations, and why each player was chosen.
import { attributeName, type TeamAttributes } from "../../../lib/tactics/attributes.ts";
import { slotLabel, type Suggestion, type TeamFormation } from "../../../lib/tactics/lineup.ts";
import { useLanguage } from "../../language";

export type SuggestionResult = { lines: number[]; suggestion: Suggestion };

export function TeamLineup({ formation, canSuggest, busy, error, result, attributes, onSuggest, onOpen }: {
  formation: TeamFormation | null;
  canSuggest: boolean;
  busy: boolean;
  error: string;
  result: SuggestionResult | null;
  attributes: TeamAttributes;
  onSuggest: () => void;
  onOpen: () => void;
}) {
  const { t, locale } = useLanguage();
  const why = (slot: Suggestion["slots"][number]) => [
    slot.position_fit === "main" ? t("Huvudposition") : slot.position_fit === "other" ? t("Kan positionen") : slot.position_fit === "group" ? t("Rätt lagdel") : null,
    ...(slot.strengths ?? []).map(key => "+ " + attributeName(key, attributes, locale)),
    ...(slot.development ?? []).map(key => "− " + attributeName(key, attributes, locale)),
  ].filter(Boolean).join(" · ");

  return (
    <div className="tb-team-lineup">
      <div className="tb-requirements-actions">
        <button type="button" className="wt-button small" disabled={busy || !canSuggest} onClick={onSuggest}>{t("Föreslå spelare")}</button>
        <button type="button" className="wt-button secondary small" onClick={onOpen}>{t("Formationer…")}</button>
      </div>
      <p className="tb-hint">{!canSuggest
        ? t("Förslag och krav finns för 5, 7, 9 och 11 spelare.")
        : formation
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
    </div>
  );
}
