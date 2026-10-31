"use client";

// The library (decision package 13): exercises, passes and sessions shared
// by coaches with the community or with a club, TeamZone's own starters, and
// each club's curated list for its teams. Shown as the start page shows
// projects: one search (words, the kind as one tap, the other filters folded
// away) over a grid of cards. Start a project from an item (a copy: later
// versions never change it), mark it a favourite, report what does not
// belong here, and remove what you shared yourself.
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { newDocument } from "../../lib/tactics/document.ts";
import { boardsFromLibrary, libraryKindLabels, noFilters, projectKindOf, type SharedFilters, type SharedItemSummary } from "../../lib/tactics/library.ts";
import type { ProjectSummary } from "../../lib/tactics/model.ts";
import { boardsFromTemplate } from "../../lib/tactics/templates.ts";
import { useAccount } from "../account";
import { useSharedLibrary } from "./use-shared-library.ts";
import { HomeFilterBar } from "./home/HomeFilterBar.tsx";
import { LibraryCard } from "./home/LibraryCard.tsx";
import "./tactics.css";
import "./home/home.css";

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

  function refresh() {
    return search(filters, source === "all" || source === "favorites" ? null : source, source === "favorites");
  }
  const toggle = async (item: SharedItemSummary, clubId: string, picked: boolean) => {
    if (await pick(clubId, item.id, picked)) void refresh();
  };
  const mark = async (item: SharedItemSummary) => {
    if (await favorite(item.id, !item.favorite)) void refresh();
  };

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

  const sources: [string, string][] = [["all", "Hela biblioteket"], ["favorites", "Mina favoriter"],
    ...clubs.map(club => [club.club_id, clubs.length > 1 ? `Klubbens lista: ${club.club_name}` : "Klubbens lista"] as [string, string])];
  const filtered = Object.values(filters).some(value => value !== "");
  return (
    <div className="tb-home">
      <div className="tb-home-actions tb-library-top">
        <Link className="wt-link" href="/tacticsboard">← Dina projekt</Link>
        <div className="tb-segments" role="group" aria-label="Visa">
          {sources.map(([value, label]) => (
            <button key={value} type="button" aria-pressed={source === value} onClick={() => setSource(value)}>{label}</button>
          ))}
        </div>
      </div>
      <p className="wt-small tb-library-intro">{listClub
        ? "Det klubben erbjuder sina lag: övningar utvalda ur hela biblioteket, och det som delats bara med klubben."
        : source === "favorites" ? "Det du har markerat med stjärnan. Du börjar också nya projekt från dem på startsidan."
        : "Övningar, pass och sessioner som tränare delar med hela communityn eller med din klubb, och TeamZones egna."} Det du använder blir en kopia i ett eget projekt.</p>
      <HomeFilterBar filters={filters} onChange={setFilters} kinds={libraryKindLabels} placeholder="Sök, t.ex. rondo eller press" />
      {(error || notice) && <p role="alert" className={error ? "wt-error" : "wt-status"}>{error || notice}</p>}
      <section aria-label="Träffar">
        {items === null ? <p className="wt-status">Laddar…</p> : items.length === 0 ? (
          <p className="tb-empty">{source === "favorites" && !filtered ? "Inga favoriter än. Tryck på stjärnan på det du vill hitta igen." : "Inget hittades. Prova med andra ord eller färre filter."}</p>
        ) : (
          <ul className="tb-grid">
            {items.map(item => (
              <LibraryCard key={item.id} item={item} keeping={keeping} busy={busy === item.id} onUse={() => void start(item)}
                onFavorite={() => void mark(item)} onPick={(clubId, picked) => void toggle(item, clubId, picked)}
                onRemove={() => void remove(item)} onReport={() => void sendReport(item)} />
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
