"use client";

// Publishing from a project (decision package 13): in a training project
// the board in hand as an exercise or the project as a pass, in teaching
// material the project as a session; with the whole community or only one
// of your clubs. Published again, it publishes the latest version and who
// sees it may change. Ties to TeamZone players never go along; your name
// shows, and those who see it may use and copy it (TBL-05, TBL-15).
import { useEffect, useState } from "react";
import { exerciseItem, lessonItem, libraryKindsFor, planItem, type LibraryKind } from "../../lib/tactics/library.ts";
import { activeBoard, useEditor, NONE } from "./store.ts";
import { useLibrary } from "./use-library.ts";
import { useSharedLibrary } from "./use-shared-library.ts";
import { PublishedIcon } from "./PublishedIcon.tsx";
import { useT } from "../language";

const nameLabels: Record<LibraryKind, string> = {
  exercise: "Övningens namn",
  plan: "Passets namn",
  lesson: "Sessionens namn",
};

export function PublishDialog({ onClose }: { onClose: () => void }) {
  const t = useT();
  const meta = useEditor(state => state.meta);
  const board = useEditor(activeBoard);
  const boards = useEditor(state => state.document?.boards ?? NONE);
  const kinds = meta ? libraryKindsFor[meta.kind] : [];
  const { items, signedIn } = useLibrary();
  const { clubs, error, publish } = useSharedLibrary();
  const [kind, setKind] = useState<LibraryKind | undefined>(kinds[0]);
  const [title, setTitle] = useState(() => (kinds[0] === "exercise" ? board?.name : meta?.name) ?? "");
  const [theme, setTheme] = useState("");
  const [goal, setGoal] = useState("");
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState<string | null>(null);
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => { if (event.key === "Escape") onClose(); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  // What this project has published, and what this board or project already is.
  const published = (items ?? []).filter(item => item.source_project_id === meta?.id && item.shared);
  const existing = published.find(item => item.kind === kind && (kind !== "exercise" || item.source_board_id === board?.id));
  const [target, setTarget] = useState<string | null>(null);
  const audience = target ?? existing?.shared?.club_id ?? "community";

  const choose = (next: LibraryKind) => {
    setKind(next);
    setTitle((next === "exercise" ? board?.name : meta?.name) ?? "");
  };

  const submit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!meta || !board || !kind || !title.trim()) return;
    const item = kind === "exercise" ? exerciseItem(board, title.trim())
      : kind === "plan" ? planItem(boards, title.trim(), theme.trim(), goal.trim())
      : lessonItem(boards, title.trim());
    setBusy(true);
    const shared = await publish(item, meta.id, kind === "exercise" ? board.id : null, audience === "community" ? null : audience);
    setBusy(false);
    if (shared) setDone(shared.club_name ? t("{title} är publicerad bara för {club} i biblioteket.", { title: title.trim(), club: shared.club_name }) : t("{title} är publicerad för hela communityn i biblioteket.", { title: title.trim() }));
  };

  return (
    <div className="tb-modal" role="dialog" aria-modal="true" aria-label={t("Publicera")} onClick={event => { if (event.target === event.currentTarget) onClose(); }}>
      <form className="tb-modal-card" onSubmit={submit}>
        <div className="tb-modal-head">
          <h2>{t("Publicera")}</h2>
          <button type="button" className="tb-modal-close" aria-label={t("Stäng")} onClick={onClose}>×</button>
        </div>
        {!signedIn ? (
          <>
            <p>{t("Logga in för att publicera övningar, pass och sessioner i biblioteket.")}</p>
            <div className="tb-actions"><button type="button" className="wt-button small" onClick={onClose}>{t("Stäng")}</button></div>
          </>
        ) : kinds.length === 0 ? (
          <>
            <p>{t("Matchens tavlor hör till laget och publiceras inte. De finns i ditt bibliotek bland dina projekt. Vill du publicera en övning eller ett pass, byt projektets typ till Träning (eller Utbildning för en session) under Projektet.")}</p>
            <div className="tb-actions"><button type="button" className="wt-button small" onClick={onClose}>{t("Stäng")}</button></div>
          </>
        ) : done ? (
          <>
            <p>{done}</p>
            <div className="tb-actions"><button type="button" className="wt-button small" onClick={onClose}>{t("Stäng")}</button></div>
          </>
        ) : (
          <>
            {published.length > 0 && (
              <ul className="tb-published">
                {published.map(item => (
                  <li key={item.id}><PublishedIcon clubName={item.shared!.club_name} />{item.title}
                    {item.shared!.current ? "" : t(" (ändrad sedan den publicerades)")}</li>
                ))}
              </ul>
            )}
            {kinds.length > 1 && (
              <div className="tb-field" role="radiogroup" aria-label={t("Vad som publiceras")}>
                {kinds.map(value => (
                  <label key={value} className="tb-check">
                    <input type="radio" name="publish-kind" checked={kind === value} onChange={() => choose(value)} />
                    {value === "exercise" ? t("Tavlan {name} som övning", { name: board?.name || t("Tavla") })
                      : boards.length === 1 ? t("Projektet som pass (1 övning)") : t("Projektet som pass ({count} övningar)", { count: boards.length })}
                  </label>
                ))}
              </div>
            )}
            <label className="tb-field">{kind ? t(nameLabels[kind]) : t("Namn")}
              <input value={title} maxLength={120} required onChange={event => setTitle(event.target.value)} />
            </label>
            {kind === "plan" && (
              <>
                <label className="tb-field">{t("Tema")}<input value={theme} maxLength={200} placeholder={t("T.ex. press och återerövring")} onChange={event => setTheme(event.target.value)} /></label>
                <label className="tb-field">{t("Passets mål")}<textarea rows={3} maxLength={2000} value={goal} onChange={event => setGoal(event.target.value)} /></label>
              </>
            )}
            <div className="tb-field" role="radiogroup" aria-label={t("Vem som ser den")}>{t("Vem ser den")}
              <label className="tb-check">
                <input type="radio" name="publish-target" checked={audience === "community"} onChange={() => setTarget("community")} />
                {t("Hela communityn: alla med Tacticsboard")}
              </label>
              {clubs.map(club => (
                <label key={club.club_id} className="tb-check">
                  <input type="radio" name="publish-target" checked={audience === club.club_id} onChange={() => setTarget(club.club_id)} />
                  {t("Bara {name}: klubbens ledare", { name: club.club_name })}
                </label>
              ))}
            </div>
            <p className="tb-hint">{t("Den publiceras med ditt namn som en låst version, och de som ser den får använda och kopiera den. Kopplingar till spelare följer inte med.")}{kind === "exercise" ? t(" Uppgifterna under Övningen och tavlans beskrivning följer med.") : ""}
              {existing ? t(" Den är redan publicerad och uppdateras till den senaste versionen.") : ""}</p>
            {error && <p className="wt-error" role="alert">{error}</p>}
            <div className="tb-actions">
              <button type="submit" className="wt-button small" disabled={busy || !title.trim()}>{busy ? t("Publicerar…") : existing ? t("Publicera den senaste versionen") : t("Publicera")}</button>
              <button type="button" className="wt-button secondary small" onClick={onClose}>{t("Avbryt")}</button>
            </div>
          </>
        )}
      </form>
    </div>
  );
}
