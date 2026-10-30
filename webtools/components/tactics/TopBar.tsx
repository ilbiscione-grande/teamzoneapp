"use client";

// Above the board, on one row: back to the projects (or the folder it was
// opened from), the boards as tabs,
// undo and redo, PDF, sharing and how saving goes. The project's name, kind
// and team are under the board's settings.
import Link from "next/link";
import { useEffect, useState } from "react";
import type { ProjectKind } from "../../lib/tactics/model.ts";
import { kindNames } from "../../lib/tactics/preview.ts";
import type { LeaderTeam } from "../../lib/tournament";
import { useAccount } from "../account";
import { useEditor, type SaveState, NONE } from "./store.ts";
import { saveNow } from "./use-autosave.ts";
import { ShareDialog } from "./ShareDialog.tsx";
import { ExportDialog } from "./export/ExportDialog.tsx";
import { BoardMenu } from "./BoardMenu.tsx";
import { LiveButton } from "./live/LiveButton.tsx";
import { LiveDialog } from "./live/LiveDialog.tsx";
import { TopBarMore } from "./TopBarMore.tsx";
import { useLibrary } from "./use-library.ts";
import { PublishedIcon } from "./PublishedIcon.tsx";

const saveLabels: Record<SaveState, string> = {
  saved: "Sparat", dirty: "Ändrat", saving: "Sparar…", error: "Kunde inte spara", conflict: "Ändrat på annat håll",
};

export const kindLabels = kindNames;

function Boards() {
  const boards = useEditor(state => state.document?.boards ?? NONE);
  const boardId = useEditor(state => state.boardId);
  const { setBoard, change } = useEditor.getState();
  const projectId = useEditor(state => state.meta?.id);
  const { items } = useLibrary();
  const publishedFor = (boardId: string) => [...new Set((items ?? [])
    .filter(item => item.shared && item.source_project_id === projectId && (item.kind !== "exercise" || item.source_board_id === boardId))
    .map(item => item.shared!.club_name ?? ""))];
  const remove = (id: string, name: string) => {
    if (boards.length < 2 || !window.confirm(`Ta bort ${name}?`)) return;
    const next = boards.find(board => board.id !== id)!;
    change(document => ({ ...document, boards: document.boards.filter(board => board.id !== id) }));
    setBoard(next.id);
  };
  return (
    <div className="tb-boards" role="tablist" aria-label="Tavlor">
      {boards.map(board => (
        <span key={board.id} className="tb-board-tab" data-active={board.id === boardId}>
          <button type="button" role="tab" aria-selected={board.id === boardId} onClick={() => setBoard(board.id)}>
            {board.name || "Tavla"}
            {publishedFor(board.id).map(club => <PublishedIcon key={club} clubName={club || null} />)}
          </button>
          {board.id === boardId && boards.length > 1 && (
            <button type="button" className="tb-tab-close" aria-label={`Ta bort ${board.name}`} onClick={() => remove(board.id, board.name)}>×</button>
          )}
        </span>
      ))}
      <BoardMenu />
    </div>
  );
}

/** The project's name, kind and TeamZone team, in the board's settings. */
export function ProjectFields({ className }: { className: string }) {
  const { client } = useAccount();
  const meta = useEditor(state => state.meta);
  const { setMeta } = useEditor.getState();
  const [teams, setTeams] = useState<LeaderTeam[]>([]);
  useEffect(() => {
    client?.schema("api").rpc("list_tournament_leader_teams").then(({ data }) => setTeams((data as LeaderTeam[] | null) ?? []));
  }, [client]);
  if (!meta) return null;
  return (
    <>
      <label className="tb-field">Namn<input value={meta.name} maxLength={120} onChange={event => setMeta({ name: event.target.value })} /></label>
      <select className={className} value={meta.kind} aria-label="Typ" onChange={event => setMeta({ kind: event.target.value as ProjectKind })}>
          {Object.entries(kindLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
        </select>
        {(teams.length > 0 || meta.teamId) && (
          <select className={className} value={meta.teamId ?? ""} aria-label="Lag i TeamZone"
            onChange={event => {
              const team = teams.find(item => item.team_id === event.target.value);
              setMeta({ teamId: team?.team_id ?? null, teamName: team?.team_name ?? null });
            }}>
            <option value="">Inget lag</option>
            {meta.teamId && !teams.some(team => team.team_id === meta.teamId) && <option value={meta.teamId}>{meta.teamName ?? "Laget"}</option>}
            {teams.map(team => <option key={team.team_id} value={team.team_id}>{team.team_name} · {team.club_name}</option>)}
          </select>
        )}
    </>
  );
}

export function TopBar({ onPresent }: { onPresent: () => void }) {
  const { client } = useAccount();
  const meta = useEditor(state => state.meta);
  const saveState = useEditor(state => state.saveState);
  const canUndo = useEditor(state => state.history.past.length > 0);
  const canRedo = useEditor(state => state.history.future.length > 0);
  const { undo, redo } = useEditor.getState();
  const [sharing, setSharing] = useState(false);
  const [exporting, setExporting] = useState(false);
  const [living, setLiving] = useState(false);
  // Opened from a folder (?mapp=<id>), back goes to the folder.
  const [folderId, setFolderId] = useState<string | null>(null);
  useEffect(() => {
    const id = new URLSearchParams(window.location.search).get("mapp");
    setFolderId(id && /^[0-9a-f-]{36}$/.test(id) ? id : null);
  }, []);
  if (!meta) return null;
  return (
    <header className="tb-top">
      {sharing && <ShareDialog onClose={() => setSharing(false)} />}
      {exporting && <ExportDialog onClose={() => setExporting(false)} />}
      {living && <LiveDialog onClose={() => setLiving(false)} />}
      <div className="tb-top-row">
        <Link href={folderId ? `/tacticsboard/mapp/${folderId}` : "/tacticsboard"} className="tb-back"
          aria-label={folderId ? "Till mappen" : "Till projekten"} title={meta.name}>‹</Link>
        <Boards />
        <button type="button" className="tb-icon" onClick={undo} disabled={!canUndo} aria-label="Ångra" title="Ångra (Ctrl+Z)">↶</button>
        <button type="button" className="tb-icon" onClick={redo} disabled={!canRedo} aria-label="Gör om" title="Gör om (Ctrl+Y)">↷</button>
        <button type="button" className="tb-icon tb-pdf tb-wide-only" onClick={onPresent} aria-label="Visa i helskärm" title="Visa i helskärm, utan redigering">⛶</button>
        <button type="button" className="tb-icon tb-pdf tb-wide-only" onClick={() => setExporting(true)} aria-label="Skapa PDF" title="Skapa PDF">PDF</button>
        <LiveButton onClick={() => setLiving(true)} />
        <TopBarMore onPresent={onPresent} onPdf={() => setExporting(true)} onLive={() => setLiving(true)} />
        <button type="button" className="tb-share" onClick={() => setSharing(true)}>Dela</button>
        <span className="tb-save" data-state={saveState} role="status">
          {saveLabels[saveState]}
          {saveState === "error" && client && <button type="button" className="tb-link" onClick={() => void saveNow(client)}>Försök igen</button>}
          {saveState === "conflict" && <button type="button" className="tb-link" onClick={() => window.location.reload()}>Hämta senaste</button>}
        </span>
      </div>
    </header>
  );
}
