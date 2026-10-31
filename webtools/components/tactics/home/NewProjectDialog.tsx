"use client";

// A new project, guided in three steps: what it is (a match, a training or
// teaching material), what it starts from (ready boards, an empty board,
// one of your templates or a favourite from TeamZone's library), then its
// name and TeamZone team, confirmed before it is made and opened. A step
// can be gone back to; a kind picked on the start page skips the first.
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { newDocument } from "../../../lib/tactics/document.ts";
import type { FolderSummary } from "../../../lib/tactics/folders.ts";
import { boardsFromLibrary, libraryKindLabels, projectKindOf, type SharedItemSummary } from "../../../lib/tactics/library.ts";
import type { Board, ProjectKind, ProjectSummary } from "../../../lib/tactics/model.ts";
import { boardsFromTemplate, defaultStarterKeys, starterBoard, starterSets, type TemplateSummary } from "../../../lib/tactics/templates.ts";
import type { LeaderTeam } from "../../../lib/tournament";
import { useAccount } from "../../account";
import { kindLabels } from "../TopBar.tsx";
import "../share.css";

export const kindHints: Record<ProjectKind, string> = {
  match: "Uppställning, matchplan och fasta situationer.",
  training: "Övningar och pass med uppvärmning, huvuddel och spel.",
  education: "Principer och spelidé att visa och gå igenom.",
};

type Props = {
  teams: LeaderTeam[];
  folder: FolderSummary | null;
  templates: TemplateSummary[] | null;
  templateBoards: (id: string) => Promise<Board[] | null>;
  removeTemplate: (id: string) => void;
  favorites: SharedItemSummary[] | null;
  favoriteBoards: (id: string) => Promise<Board[] | null>;
  addToFolder: (folderId: string, projectId: string) => Promise<unknown>;
  kind?: ProjectKind;
  onClose: () => void;
};

// "ready" for the ready boards, "empty" for one empty board, "template:<id>" or "favorite:<id>".
type Start = string;

export function NewProjectDialog({ teams, folder, templates, templateBoards, removeTemplate, favorites, favoriteBoards, addToFolder, kind: preset, onClose }: Props) {
  const { client } = useAccount();
  const router = useRouter();
  const [step, setStep] = useState(preset ? 2 : 1);
  const [kind, setKind] = useState<ProjectKind>(preset ?? "match");
  const [start, setStart] = useState<Start>("ready");
  const [picked, setPicked] = useState<string[]>(defaultStarterKeys[preset ?? "match"]);
  const [name, setName] = useState("");
  const [teamId, setTeamId] = useState(teams.length === 1 ? teams[0].team_id : "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => { if (event.key === "Escape" && !busy) onClose(); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [busy, onClose]);

  const template = templates?.find(item => `template:${item.id}` === start);
  const favorite = favorites?.find(item => `favorite:${item.id}` === start);
  const pickKind = (value: ProjectKind) => {
    setKind(value);
    setPicked(defaultStarterKeys[value]);
    if (start !== "empty") setStart("ready");
    setStep(2);
  };
  const pickStart = (value: Start) => {
    setStart(value);
    const chosenTemplate = templates?.find(item => `template:${item.id}` === value);
    if (chosenTemplate) setKind(chosenTemplate.kind);
    const chosenFavorite = favorites?.find(item => `favorite:${item.id}` === value);
    if (chosenFavorite) { setKind(projectKindOf[chosenFavorite.kind]); if (!name) setName(chosenFavorite.title); }
  };
  const startLabel = start === "ready"
    ? `Färdiga tavlor: ${starterSets[kind].filter(item => picked.includes(item.key)).map(item => item.name).join(", ") || "en tom tavla"}`
    : start === "empty" ? "En tom tavla"
    : template ? `Mallen ${template.name}` : favorite ? `Favoriten ${favorite.title}` : "";

  const create = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!client) return;
    setBusy(true); setError("");
    const team = teams.find(item => item.team_id === teamId);
    let boards: Board[] | null;
    if (start === "ready" || start === "empty") {
      const chosen = start === "ready" ? starterSets[kind].filter(item => picked.includes(item.key)) : [];
      boards = chosen.length > 0 ? chosen.map(item => starterBoard(item, team?.team_name)) : newDocument("Tavla 1", team?.team_name).boards;
    } else if (favorite) {
      const found = await favoriteBoards(favorite.id);
      boards = found && boardsFromTemplate(boardsFromLibrary(favorite, found), team?.team_name);
    } else if (template) {
      const found = await templateBoards(template.id);
      boards = found && boardsFromTemplate(found, team?.team_name);
    } else boards = null;
    if (!boards) { setBusy(false); setError("Det du valde att börja från kunde inte hämtas. Försök igen."); return; }
    const { data, error: createError } = await client.schema("api").rpc("create_tactics_project", {
      project_name: name.trim() || "Namnlöst projekt", project_kind: kind, target_team_id: team?.team_id ?? null,
      project_document: { ...newDocument(), boards },
    });
    if (createError) { setBusy(false); setError("Projektet kunde inte skapas. Försök igen."); return; }
    const created = (data as ProjectSummary).id;
    // Not put in the folder, the project is still made; the folder page tells.
    if (folder) await addToFolder(folder.id, created);
    router.push(folder ? `/tacticsboard/${created}?mapp=${folder.id}` : `/tacticsboard/${created}`);
  };

  const ownTemplates = (templates ?? []).filter(item => item.kind === kind);
  const otherTemplates = (templates ?? []).filter(item => item.kind !== kind);
  const steps = ["Typ", "Börja från", "Namn och lag"];
  return (
    <div className="tb-modal" role="dialog" aria-modal="true" aria-label="Nytt projekt" onClick={event => { if (event.target === event.currentTarget && !busy) onClose(); }}>
      <form className="tb-modal-card tb-new" onSubmit={create}>
        <div className="tb-modal-head">
          <h2>Nytt projekt</h2>
          <button type="button" className="tb-modal-close" aria-label="Stäng" onClick={onClose} disabled={busy}>×</button>
        </div>
        <ol className="tb-steps" aria-label="Steg">
          {steps.map((label, index) => (
            <li key={label} className={index + 1 === step ? "now" : index + 1 < step ? "done" : ""} aria-current={index + 1 === step ? "step" : undefined}>
              <button type="button" disabled={index + 1 > step || busy} onClick={() => setStep(index + 1)}>
                <span>{index + 1}</span>{label}
              </button>
            </li>
          ))}
        </ol>

        {step === 1 && (
          <div className="tb-choices tb-kinds">
            {(Object.keys(kindLabels) as ProjectKind[]).map(value => (
              <button key={value} type="button" className={`tb-choice${kind === value ? " on" : ""}`} onClick={() => pickKind(value)}>
                <span className={`tb-choice-icon tb-kind-${value}`} aria-hidden="true">{kindLabels[value].slice(0, 1)}</span>
                <strong>{kindLabels[value]}</strong>
                <span>{kindHints[value]}</span>
              </button>
            ))}
          </div>
        )}

        {step === 2 && (
          <>
            <p className="tb-hint">Börja från något färdigt så slipper du rita allt själv. Allt går att ändra sedan.</p>
            <div className="tb-choices" role="radiogroup" aria-label="Börja från">
              <StartChoice value="ready" start={start} onPick={pickStart} title={`Färdiga tavlor för ${kindLabels[kind].toLowerCase()}`}
                text="Välj vilka tavlor projektet börjar med." />
              <StartChoice value="empty" start={start} onPick={pickStart} title="Tom tavla" text="En plan att rita på från början." />
              {ownTemplates.map(item => (
                <StartChoice key={item.id} value={`template:${item.id}`} start={start} onPick={pickStart} title={item.name}
                  badge="Din mall" text={item.boards.map(board => board.name).join(", ")}
                  onRemove={() => { if (window.confirm(`Ta bort mallen ${item.name}?`)) { if (start === `template:${item.id}`) setStart("ready"); removeTemplate(item.id); } }} />
              ))}
              {(favorites ?? []).filter(item => projectKindOf[item.kind] === kind).map(item => (
                <StartChoice key={item.id} value={`favorite:${item.id}`} start={start} onPick={pickStart} title={item.title}
                  badge={`Favorit · ${libraryKindLabels[item.kind]}`} text={item.boards.map(board => board.name).join(", ")} />
              ))}
            </div>
            {start === "ready" && (
              <fieldset className="tb-starters">
                <legend>Tavlor att börja med</legend>
                {starterSets[kind].map(item => (
                  <label key={item.key}>
                    <input type="checkbox" checked={picked.includes(item.key)}
                      onChange={event => setPicked(event.target.checked ? [...picked, item.key] : picked.filter(key => key !== item.key))} />
                    {item.name}
                  </label>
                ))}
              </fieldset>
            )}
            {otherTemplates.length > 0 && (
              <details className="tb-more-starts">
                <summary>Mallar för andra typer ({otherTemplates.length})</summary>
                <div className="tb-choices">
                  {otherTemplates.map(item => (
                    <StartChoice key={item.id} value={`template:${item.id}`} start={start} onPick={pickStart} title={item.name}
                      badge={`Din mall · ${kindLabels[item.kind]}`} text={item.boards.map(board => board.name).join(", ")} />
                  ))}
                </div>
              </details>
            )}
            {(templates ?? []).length === 0 && (
              <p className="wt-small">Spara ett projekt som mall i projektet under Tavlan → Spara som mall, så finns den här nästa gång.</p>
            )}
          </>
        )}

        {step === 3 && (
          <div className="wt-form">
            <label>Namn
              <input autoFocus value={name} onChange={event => setName(event.target.value)} maxLength={120}
                placeholder={kind === "match" ? "T.ex. Match mot Aneby SK" : kind === "training" ? "T.ex. Passning och spelvändning" : "T.ex. Spelidé: speluppbyggnad"} />
            </label>
            {teams.length > 0 && (
              <label>Lag i TeamZone
                <select value={teamId} onChange={event => setTeamId(event.target.value)}>
                  <option value="">Inget lag</option>
                  {teams.map(team => <option key={team.team_id} value={team.team_id}>{team.team_name} · {team.club_name}</option>)}
                </select>
                <span className="wt-small">Med ett lag hämtar du truppen till tavlan, och lagets andra ledare kan se projektet.</span>
              </label>
            )}
            <dl className="tb-new-summary">
              <dt>Typ</dt><dd>{kindLabels[kind]}</dd>
              <dt>Börjar från</dt><dd>{startLabel}</dd>
              {folder && <><dt>Mapp</dt><dd>{folder.name}</dd></>}
            </dl>
          </div>
        )}

        {error && <p role="alert" className="wt-error">{error}</p>}
        <div className="tb-actions tb-new-actions">
          {step > 1 && <button type="button" className="wt-button secondary small" disabled={busy} onClick={() => setStep(step - 1)}>Tillbaka</button>}
          {step === 2 && <button type="button" className="wt-button small" onClick={() => setStep(3)}>Nästa</button>}
          {step === 3 && <button type="submit" className="wt-button small" disabled={busy}>{busy ? "Skapar…" : "Skapa och öppna"}</button>}
        </div>
      </form>
    </div>
  );
}

type ChoiceProps = { value: Start; start: Start; onPick: (value: Start) => void; title: string; text: string; badge?: string; onRemove?: () => void };

function StartChoice({ value, start, onPick, title, text, badge, onRemove }: ChoiceProps) {
  return (
    <div className={`tb-choice${start === value ? " on" : ""}`}>
      <button type="button" role="radio" aria-checked={start === value} className="tb-choice-main" onClick={() => onPick(value)}>
        {badge && <span className="tb-choice-badge">{badge}</span>}
        <strong>{title}</strong>
        {text && <span>{text}</span>}
      </button>
      {onRemove && <button type="button" className="tb-choice-remove" aria-label={`Ta bort mallen ${title}`} title="Ta bort mallen" onClick={onRemove}>×</button>}
    </div>
  );
}
