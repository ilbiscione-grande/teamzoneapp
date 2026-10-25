"use client";

// The library (decision package 13): exercises, passes and sessions shared
// by coaches with the community or with a club, TeamZone's own starters, and
// each club's curated list for its teams. Search by words
// and filter on kind, part, phase, age class and game form; start a project
// from an item (a copy: later versions never change it), report what does
// not belong here, and remove what you shared yourself.
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { newDocument } from "../../lib/tactics/document.ts";
import {
  ageClasses, ageClassLabels, boardsFromLibrary, gameFormLabels, gameForms, libraryKindLabels, librarySummaryLine,
  noFilters, partLabels, phaseLabels, projectKindOf, type SharedFilters, type SharedItemSummary,
} from "../../lib/tactics/library.ts";
import type { ProjectSummary } from "../../lib/tactics/model.ts";
import { boardsFromTemplate } from "../../lib/tactics/templates.ts";
import { useAccount } from "../account";
import { useSharedLibrary } from "./use-shared-library.ts";
import "./tactics.css";

export function SharedLibrary() {
  const { client } = useAccount();
  const router = useRouter();
  const { items, error, clubs, search, boardsOf, unshare, report, pick, favorite } = useSharedLibrary();
  // "all", "favorites", or a club's id for that club's list.
  const [source, setSource] = useState("all");
  const listClub = clubs.find(club => club.club_id === source);
  const keeping = clubs.filter(club => club.can_manage);
  const [filters, setFilters] = useState<SharedFilters>(noFilters);
  const [busy, setBusy] = useState<string | null>(null);
  const [notice, setNotice] = useState("");

  // Searches as the filters change, a moment after typing stops.
  useEffect(() => {
    const timer = window.setTimeout(() => void refresh(), filters.text ? 300 : 0);
    return () => window.clearTimeout(timer);
  }, [filters, source, search]);

  const toggle = async (item: SharedItemSummary, clubId: string, picked: boolean) => {
    if (await pick(clubId, item.id, picked)) void refresh();
  };
  const mark = async (item: SharedItemSummary) => {
    if (await favorite(item.id, !item.favorite)) void refresh();
  };

  const set = (patch: Partial<SharedFilters>) => setFilters(current => ({ ...current, ...patch }));
  function refresh() {
    return search(filters, source === "all" || source === "favorites" ? null : source, source === "favorites");
  }

  const start = async (item: SharedItemSummary) => {
    if (!client) return;
    setBusy(item.id);
    const boards = await boardsOf(item.id);
    if (!boards) { setBusy(null); return; }
    const { data, error: createError } = await client.schema("api").rpc("create_tactics_project", {
      project_name: item.title, project_kind: projectKindOf[item.kind], target_team_id: null,
      project_document: { ...newDocument(), boards: boardsFromTemplate(boardsFromLibrary(item, boards)) },
    });
    setBusy(null);
    if (createError) { setNotice("Projektet kunde inte skapas. Försök igen."); return; }
    router.push(`/tacticsboard/${(data as ProjectSummary).id}`);
  };

  const sendReport = async (item: SharedItemSummary) => {
    const reason = window.prompt(`Vad är fel med ${item.title}? TeamZones support tittar på rapporten.`);
    if (!reason?.trim()) return;
    if (await report(item.id, reason)) setNotice("Tack, rapporten är skickad.");
  };

  const remove = async (item: SharedItemSummary) => {
    if (!window.confirm(item.mine
      ? `Sluta dela ${item.title}? Den finns kvar i ditt bibliotek, och de som redan använt den behåller sina kopior.`
      : `Ta bort ${item.title} ur klubbens bibliotek? De som redan använt den behåller sina kopior.`)) return;
    if (await unshare(item.id)) void refresh();
  };

  return (
    <div className="bk-home">
      <p className="wt-small"><Link className="wt-link" href="/tacticsboard">← Dina projekt och ditt bibliotek</Link></p>
      <section className="wt-panel">
        <h2>{listClub ? `Klubbens lista: ${listClub.club_name}` : source === "favorites" ? "Mina favoriter" : "Sök i biblioteket"}</h2>
        <p className="wt-small">{listClub
          ? "Det klubben erbjuder sina lag: övningar utvalda ur hela biblioteket, och det som delats bara med klubben."
          : "Övningar, pass och sessioner som tränare delar med hela communityn eller med din klubb, och TeamZones egna."} Det du använder blir en kopia i ett eget projekt.</p>
        <div className="wt-form">
          <label>Visa
            <select value={source} onChange={event => setSource(event.target.value)}>
              <option value="all">Hela biblioteket</option>
              <option value="favorites">Mina favoriter</option>
              {clubs.map(club => <option key={club.club_id} value={club.club_id}>Klubbens lista: {club.club_name}</option>)}
            </select>
          </label>
          <label>Sök<input value={filters.text} maxLength={100} placeholder="T.ex. rondo eller press" onChange={event => set({ text: event.target.value })} /></label>
          <div className="bk-times tb-filters">
            <label>Typ
              <select value={filters.kind} onChange={event => set({ kind: event.target.value as SharedFilters["kind"] })}>
                <option value="">Alla</option>
                {Object.entries(libraryKindLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
              </select>
            </label>
            <label>Del av passet
              <select value={filters.part} onChange={event => set({ part: event.target.value as SharedFilters["part"] })}>
                <option value="">Alla</option>
                {Object.entries(partLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
              </select>
            </label>
            <label>Skede
              <select value={filters.phase} onChange={event => set({ phase: event.target.value as SharedFilters["phase"] })}>
                <option value="">Alla</option>
                {Object.entries(phaseLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
              </select>
            </label>
            <label>Ålder
              <select value={filters.age} onChange={event => set({ age: event.target.value as SharedFilters["age"] })}>
                <option value="">Alla</option>
                {ageClasses.map(age => <option key={age} value={age}>{ageClassLabels[age]}</option>)}
              </select>
            </label>
            <label>Spelform
              <select value={filters.form} onChange={event => set({ form: event.target.value as SharedFilters["form"] })}>
                <option value="">Alla</option>
                {gameForms.map(form => <option key={form} value={form}>{gameFormLabels[form]}</option>)}
              </select>
            </label>
          </div>
        </div>
      </section>
      {(error || notice) && <p role="alert" className={error ? "wt-error" : "wt-status"}>{error || notice}</p>}
      <section className="wt-panel" aria-label="Träffar">
        {items === null ? <p className="wt-status">Laddar…</p> : items.length === 0 ? <p>Inget hittades. Prova med andra ord eller färre filter.</p> : (
          <ul className="bk-resource-list">
            {items.map(item => (
              <li key={item.id}>
                <div>
                  <strong>{item.title}</strong>
                  <span>{[libraryKindLabels[item.kind], librarySummaryLine(item)].filter(Boolean).join(" · ")}</span>
                  <span>{[item.starter ? "TeamZone" : `Delad av ${item.author}`, item.club_name && `bara för ${item.club_name}`,
                    item.version > 1 && `version ${item.version}`, item.hidden && "dold efter rapporter",
                    item.picked_by_clubs.length > 0 && `i klubbens lista`].filter(Boolean).join(" · ")}</span>
                </div>
                <div className="wt-actions">
                  <button type="button" className="wt-button small" disabled={busy === item.id} onClick={() => void start(item)}>
                    {busy === item.id ? "Skapar…" : "Nytt projekt"}
                  </button>
                  <button type="button" className="wt-button secondary small" aria-pressed={item.favorite} onClick={() => void mark(item)}>
                    {item.favorite ? "★ Favorit" : "☆ Favorit"}
                  </button>
                  {keeping.filter(club => !item.club_id || item.club_id === club.club_id).map(club => {
                    // What is shared only with the club is in its list already.
                    if (item.club_id === club.club_id || item.hidden) return null;
                    const picked = item.picked_by_clubs.includes(club.club_id);
                    const label = picked ? "Ta bort ur klubbens lista" : "Lägg i klubbens lista";
                    return (
                      <button key={club.club_id} type="button" className="wt-button secondary small" title={club.club_name}
                        onClick={() => void toggle(item, club.club_id, !picked)}>{keeping.length > 1 ? `${label}: ${club.club_name}` : label}</button>
                    );
                  })}
                  {item.can_remove && <button type="button" className="wt-button secondary small" onClick={() => void remove(item)}>{item.mine ? "Sluta dela" : "Ta bort"}</button>}
                  {!item.mine && !item.hidden && <button type="button" className="wt-button secondary small" onClick={() => void sendReport(item)}>Rapportera</button>}
                </div>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
