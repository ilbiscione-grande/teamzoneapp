"use client";

// Above the board: back to the projects, the project's name and kind, its
// TeamZone team, the boards as tabs, undo and redo, and how saving goes.
import Link from "next/link";
import { useEffect, useState } from "react";
import { newBoard } from "../../lib/tactics/document.ts";
import type { ProjectKind } from "../../lib/tactics/model.ts";
import type { LeaderTeam } from "../../lib/tournament";
import { useAccount } from "../account";
import { useEditor, type SaveState, NONE } from "./store.ts";
import { saveNow } from "./use-autosave.ts";
import { ShareDialog } from "./ShareDialog.tsx";

const saveLabels: Record<SaveState, string> = {
  saved: "Sparat", dirty: "Ändrat", saving: "Sparar…", error: "Kunde inte spara", conflict: "Ändrat på annat håll",
};

export const kindLabels: Record<ProjectKind, string> = { match: "Match", training: "Träning", education: "Utbildning" };

function Boards() {
  const boards = useEditor(state => state.document?.boards ?? NONE);
  const boardId = useEditor(state => state.boardId);
  const { setBoard, change } = useEditor.getState();
  const add = () => {
    const board = newBoard(`Tavla ${boards.length + 1}`, boards[0]?.teams.home.name, boards[0]?.teams.away.name);
    change(document => ({ ...document, boards: [...document.boards, board] }));
    setBoard(board.id);
  };
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
          <button type="button" role="tab" aria-selected={board.id === boardId} onClick={() => setBoard(board.id)}>{board.name || "Tavla"}</button>
          {board.id === boardId && boards.length > 1 && (
            <button type="button" className="tb-tab-close" aria-label={`Ta bort ${board.name}`} onClick={() => remove(board.id, board.name)}>×</button>
          )}
        </span>
      ))}
      <button type="button" className="tb-board-add" onClick={add} aria-label="Ny tavla">+ Tavla</button>
    </div>
  );
}

/** The project's kind and TeamZone team: in the top bar, and on a phone in the board's settings. */
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

export function TopBar() {
  const { client } = useAccount();
  const meta = useEditor(state => state.meta);
  const saveState = useEditor(state => state.saveState);
  const canUndo = useEditor(state => state.history.past.length > 0);
  const canRedo = useEditor(state => state.history.future.length > 0);
  const { undo, redo, setMeta } = useEditor.getState();
  const [sharing, setSharing] = useState(false);
  if (!meta) return null;
  return (
    <header className="tb-top">
      {sharing && <ShareDialog onClose={() => setSharing(false)} />}
      <div className="tb-top-row">
        <Link href="/tacticsboard" className="tb-back" aria-label="Till projekten">‹</Link>
        <input className="tb-name" value={meta.name} maxLength={120} aria-label="Projektets namn" onChange={event => setMeta({ name: event.target.value })} />
        <span className="tb-desktop-only"><ProjectFields className="tb-select" /></span>
        <span className="tb-spacer" />
        <button type="button" className="tb-icon" onClick={undo} disabled={!canUndo} aria-label="Ångra" title="Ångra (Ctrl+Z)">↶</button>
        <button type="button" className="tb-icon" onClick={redo} disabled={!canRedo} aria-label="Gör om" title="Gör om (Ctrl+Y)">↷</button>
        <button type="button" className="tb-share" onClick={() => setSharing(true)}>Dela</button>
        <span className="tb-save" data-state={saveState} role="status">
          {saveLabels[saveState]}
          {saveState === "error" && client && <button type="button" className="tb-link" onClick={() => void saveNow(client)}>Försök igen</button>}
          {saveState === "conflict" && <button type="button" className="tb-link" onClick={() => window.location.reload()}>Hämta senaste</button>}
        </span>
      </div>
      <Boards />
    </header>
  );
}
