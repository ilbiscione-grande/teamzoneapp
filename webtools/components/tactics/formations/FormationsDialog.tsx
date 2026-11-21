"use client";

// The team's formations, and ready-made ones, with what each place asks for.
// A ready-made formation cannot be changed: a copy is saved with the team and
// changed instead. The team's formations are saved with the team in TeamZone,
// so every board (and the app's line-up) can use them. From here a formation
// is put on the board, or players are suggested for it.
import { useState } from "react";
import type { TeamAttributes } from "../../../lib/tactics/attributes.ts";
import { byFormat, formationSlots, formatName, linesOf, matchFormat, type FormationSlot, type TeamFormation } from "../../../lib/tactics/lineup.ts";
import { parseFormation } from "../../../lib/tactics/formations.ts";
import { useLanguage } from "../../language";
import type { FormationDraft } from "../use-team-formations.ts";
import { FormationPitch } from "./FormationPitch.tsx";
import { SlotEditor } from "./SlotEditor.tsx";

export type FormationUse = "place" | "suggest";

const draftOf = (formation: TeamFormation): FormationDraft => ({
  id: formation.template ? null : formation.id, name: formation.name, lines: formation.lines,
  matchFormat: formation.match_format, slots: formation.slots, revision: formation.template ? null : formation.revision,
});

export function FormationsDialog({ formations, templates, attributes, initial, onSave, onDelete, onUse, onClose }: {
  formations: TeamFormation[];
  templates: TeamFormation[];
  attributes: TeamAttributes;
  /** The formation chosen on the board, opened first. */
  initial: string | null;
  onSave: (draft: FormationDraft) => Promise<TeamFormation | string>;
  onDelete: (formationId: string) => Promise<boolean>;
  onUse: (formation: TeamFormation, use: FormationUse) => void;
  onClose: () => void;
}) {
  const { t, locale } = useLanguage();
  const english = locale === "en";
  const all = [...formations, ...templates];
  const [chosenId, setChosenId] = useState<string | null>(
    all.find(item => item.id === initial)?.id ?? formations[0]?.id ?? templates[0]?.id ?? null);
  const chosen = all.find(item => item.id === chosenId) ?? null;
  // The chosen team formation as it is being changed; null when unchanged.
  const [draft, setDraft] = useState<FormationDraft | null>(null);
  const [slotCode, setSlotCode] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);
  const [newName, setNewName] = useState("");
  const [newLines, setNewLines] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  const shown = draft ?? (chosen ? draftOf(chosen) : null);
  const lines = shown ? linesOf(shown.lines) : [];
  const readOnly = !!chosen?.template;
  const dirty = draft !== null;
  const slot = shown?.slots.find(item => item.code === slotCode) ?? shown?.slots[0] ?? null;

  const leaveChanges = () => !dirty || window.confirm(t("Formationen har ändringar som inte är sparade. Släpp dem?"));
  const choose = (id: string) => {
    if (id === chosenId || !leaveChanges()) return;
    setChosenId(id); setDraft(null); setSlotCode(null); setCreating(false); setError("");
  };
  const change = (next: Partial<FormationDraft>) => shown && setDraft({ ...shown, ...next });
  const changeSlot = (next: FormationSlot) => shown && change({ slots: shown.slots.map(item => item.code === next.code ? next : item) });

  const problem = (message: string) => message === "formation_name_taken" ? t("Laget har redan en formation med det namnet.")
    : message === "stale_revision" ? t("Någon annan har ändrat formationen. Stäng och öppna den igen.")
    : message === "too_many_formations" ? t("Laget kan ha högst 30 formationer.")
    : t("Formationen kunde inte sparas.");

  const save = async (next: FormationDraft) => {
    setBusy(true); setError("");
    const saved = await onSave(next);
    setBusy(false);
    if (typeof saved === "string") { setError(problem(saved)); return false; }
    setChosenId(saved.id); setDraft(null); setCreating(false);
    return true;
  };

  // A copy of a template (or of a team formation) is saved with the team at once, then changed.
  const copy = () => {
    if (!shown) return;
    const taken = new Set(formations.map(item => item.name.toLowerCase()));
    let name = t("{name} (kopia)", { name: shown.name });
    for (let n = 2; taken.has(name.toLowerCase()); n++) name = t("{name} (kopia {n})", { name: shown.name, n });
    void save({ ...shown, id: null, revision: null, name });
  };

  const create = () => {
    const parsed = parseFormation(newLines);
    const format = parsed ? matchFormat(parsed) : null;
    if (!parsed || !format) { setError(t("Skriv raderna bakifrån, t.ex. 4-4-2, för 5, 7, 9 eller 11 spelare.")); return; }
    void save({ id: null, revision: null, name: newName.trim() || parsed.join("-"), lines: parsed.join("-"), matchFormat: format,
      slots: formationSlots(parsed).map(item => ({ ...item, position: null, requirements: [] })) });
  };

  const remove = async () => {
    if (!chosen || chosen.template || !window.confirm(t("Ta bort formationen för hela laget?"))) return;
    setBusy(true);
    const removed = await onDelete(chosen.id);
    setBusy(false);
    if (!removed) { setError(t("Formationen kunde inte tas bort.")); return; }
    setChosenId(templates[0]?.id ?? null); setDraft(null);
  };

  const close = () => { if (leaveChanges()) onClose(); };
  const use = (how: FormationUse) => { if (chosen && !dirty) onUse(chosen, how); };

  const item = (formation: TeamFormation) => (
    <li key={formation.id}>
      <button type="button" data-chosen={formation.id === chosenId} onClick={() => choose(formation.id)}>
        <span>{formation.name}</span>
        {formation.name !== formation.lines && <small>{formation.lines}</small>}
      </button>
    </li>
  );

  return (
    <div className="tb-modal" role="dialog" aria-label={t("Formationer")} onClick={close}>
      <div className="tb-modal-card tb-formations" onClick={event => event.stopPropagation()}>
        <div className="tb-modal-head">
          <h2>{t("Formationer")}</h2>
          <button type="button" className="tb-modal-close" aria-label={t("Stäng")} onClick={close}>×</button>
        </div>
        <div className="tb-formations-body">
          <nav className="tb-formations-list" aria-label={t("Formationer")}>
            <div className="tb-formations-group">
              <h3>{t("Lagets formationer")}</h3>
              {formations.length === 0 && <p className="tb-hint">{t("Inga än. Gör en kopia av en mall, eller en ny.")}</p>}
              <ul>{formations.map(item)}</ul>
              {creating ? (
                <div className="tb-formations-new">
                  <input value={newName} placeholder={t("Namn")} maxLength={60} onChange={event => setNewName(event.target.value)} />
                  <input value={newLines} placeholder={t("T.ex. 3-1-4-2")} onChange={event => setNewLines(event.target.value)} />
                  <div className="tb-requirements-actions">
                    <button type="button" className="wt-button small" disabled={busy || !newLines.trim()} onClick={create}>{t("Skapa")}</button>
                    <button type="button" className="wt-link-button" onClick={() => setCreating(false)}>{t("Avbryt")}</button>
                  </div>
                </div>
              ) : (
                <button type="button" className="wt-link-button" onClick={() => { if (leaveChanges()) { setDraft(null); setCreating(true); } }}>{t("+ Ny formation")}</button>
              )}
            </div>
            {byFormat(templates).map(([format, items]) => (
              <div key={format} className="tb-formations-group">
                <h3>{t("Mallar · {format}", { format: formatName(format, english) })}</h3>
                <ul>{items.map(item)}</ul>
              </div>
            ))}
          </nav>
          {shown ? (
            <section className="tb-formations-detail">
              <div className="tb-formations-title">
                {readOnly ? (
                  <h3>{shown.name} <span className="tb-badge">{t("Mall")}</span></h3>
                ) : (
                  <input aria-label={t("Namn")} value={shown.name} maxLength={60} onChange={event => change({ name: event.target.value })} />
                )}
                <span className="tb-hint">{shown.lines} · {formatName(shown.matchFormat, english)}</span>
              </div>
              <p className="tb-hint">{readOnly
                ? t("Mallen går inte att ändra. Gör en egen kopia, som sparas med laget, och ändra den.")
                : t("Klicka på en plats för att ändra vad den kräver. Sparas med laget i TeamZone och kan användas på alla tavlor och i appens laguttagning.")}</p>
              <div className="tb-formations-work">
                <FormationPitch lines={lines} slots={shown.slots} selected={slot?.code ?? null} english={english} onSelect={setSlotCode} />
                {slot && <SlotEditor key={`${shown.id ?? shown.lines}-${slot.code}`} slot={slot} lines={lines} attributes={attributes} readOnly={readOnly} onChange={changeSlot} />}
              </div>
              {error && <p className="wt-error" role="alert">{error}</p>}
              <div className="tb-formations-actions">
                {readOnly ? (
                  <button type="button" className="wt-button small" disabled={busy} onClick={copy}>{t("Gör en egen kopia")}</button>
                ) : (
                  <>
                    <button type="button" className="wt-button small" disabled={busy || !dirty || !shown.name.trim()} onClick={() => draft && void save(draft)}>
                      {dirty ? t("Spara ändringarna") : t("Sparad")}
                    </button>
                    {dirty && <button type="button" className="wt-link-button" disabled={busy} onClick={() => setDraft(null)}>{t("Ångra ändringarna")}</button>}
                    <button type="button" className="wt-link-button" disabled={busy || dirty} onClick={copy}>{t("Kopiera")}</button>
                    <button type="button" className="wt-link-button" disabled={busy} onClick={() => void remove()}>{t("Ta bort")}</button>
                  </>
                )}
                <span className="tb-formations-use">
                  <button type="button" className="wt-button secondary small" disabled={busy || dirty} onClick={() => use("place")}>{t("Ställ upp laget")}</button>
                  <button type="button" className="wt-button small" disabled={busy || dirty} onClick={() => use("suggest")}>{t("Föreslå spelare")}</button>
                </span>
              </div>
              {dirty && <p className="tb-hint">{t("Spara ändringarna innan formationen används på tavlan.")}</p>}
            </section>
          ) : <p className="tb-hint">{t("Välj en formation.")}</p>}
        </div>
      </div>
    </div>
  );
}
