"use client";

// Above the board, on one row: back to the projects (or the folder it was
// opened from), the boards as tabs (renamed by a double click; a list to choose from on a phone),
// undo and redo, presenting, versions and settings, sharing (a link, PDF,
// video and more, in one dialog) and how saving goes. The project's name, kind and team are under Inställningar.
import Link from "next/link";
import { useEffect, useState } from "react";
import type { LeaderAccess, ProjectKind } from "../../lib/tactics/model.ts";
import { kindNames } from "../../lib/tactics/preview.ts";
import { updateBoard } from "../../lib/tactics/document.ts";
import type { LeaderTeam } from "../../lib/tournament";
import { useAccount } from "../account";
import { useEditor, type SaveState, NONE } from "./store.ts";
import { saveAsCopy, saveNow } from "./use-autosave.ts";
import { copyProject } from "./copy-project.ts";
import { ShareDialog } from "./ShareDialog.tsx";
import { useCropping } from "./stage/CropFrame.tsx";
import { BoardMenu } from "./BoardMenu.tsx";
import { usePhone } from "./ViewerTools.tsx";
import { LiveButton } from "./live/LiveButton.tsx";
import { LiveDialog } from "./live/LiveDialog.tsx";
import { TopBarMore } from "./TopBarMore.tsx";
import { HistoryIcon, VersionsDialog } from "./VersionsDialog.tsx";
import { useLibrary } from "./use-library.ts";
import { PublishedIcon } from "./PublishedIcon.tsx";
import { SettingsDialog, useSettings } from "./SettingsDialog.tsx";
import { FullscreenIcon, SettingsIcon, ShareIcon } from "./TopBarIcons.tsx";
import { useT } from "../language";

const saveLabels: Record<SaveState, string> = {
  saved: "Sparat", dirty: "Ändrat", saving: "Sparar…", error: "Kunde inte spara", conflict: "Ändrat på annat håll",
};

export const kindLabels = kindNames;

/** The two actions at the end of a phone's list of boards. */
const RENAME = "rename", REMOVE = "remove";

function Boards() {
  const t = useT();
  const boards = useEditor(state => state.document?.boards ?? NONE);
  const boardId = useEditor(state => state.boardId);
  const { setBoard, change } = useEditor.getState();
  const projectId = useEditor(state => state.meta?.id);
  const { items } = useLibrary();
  const [renaming, setRenaming] = useState<string | null>(null);
  const phone = usePhone();
  // On a phone the tabs scroll sideways; the board you are on stays in view,
  // and on the last one so does "+" after it.
  useEffect(() => {
    const tab = document.querySelector(".tb-board-tab[data-active='true']");
    if (!tab?.parentElement) return;
    if (tab.nextElementSibling?.classList.contains("tb-board-tab")) tab.scrollIntoView({ block: "nearest", inline: "nearest" });
    else tab.parentElement.scrollLeft = tab.parentElement.scrollWidth;
  }, [boardId, boards.length]);
  const rename = (id: string, name: string) => change(document => updateBoard(document, id, current => ({ ...current, name: name.slice(0, 60) })));
  const publishedFor = (boardId: string) => [...new Set((items ?? [])
    .filter(item => item.shared && item.source_project_id === projectId && (item.kind !== "exercise" || item.source_board_id === boardId))
    .map(item => item.shared!.club_name ?? ""))];
  const remove = (id: string, name: string) => {
    if (boards.length < 2 || !window.confirm(`Ta bort ${name}?`)) return;
    const next = boards.find(board => board.id !== id)!;
    change(document => ({ ...document, boards: document.boards.filter(board => board.id !== id) }));
    setBoard(next.id);
  };
  // A phone: the boards in a list to choose from, renaming and removing last in it, and "+" beside.
  if (phone) {
    const current = boards.find(board => board.id === boardId);
    const choose = (value: string) => {
      if (value === RENAME && current) {
        const name = window.prompt(t("Tavlans namn"), current.name)?.trim();
        if (name) rename(current.id, name);
      } else if (value === REMOVE && current) remove(current.id, current.name);
      else setBoard(value);
    };
    return (
      <div className="tb-boards tb-boards-phone">
        <select className="tb-board-select" value={boardId ?? ""} aria-label={t("Tavla")} onChange={event => choose(event.target.value)}>
          {boards.map(board => <option key={board.id} value={board.id}>{board.name || t("Tavla")}</option>)}
          <option disabled>──────────</option>
          <option value={RENAME}>{t("Byt namn…")}</option>
          {boards.length > 1 && <option value={REMOVE}>{t("Ta bort tavlan…")}</option>}
        </select>
        <BoardMenu />
      </div>
    );
  }
  return (
    <div className="tb-boards" role="tablist" aria-label={t("Tavlor")}>
      {boards.map(board => (
        <span key={board.id} className="tb-board-tab" data-active={board.id === boardId}>
          {renaming === board.id ? (
            <input autoFocus defaultValue={board.name} maxLength={60} aria-label={t("Tavlans namn")} onFocus={event => event.target.select()}
              onBlur={event => { rename(board.id, event.target.value.trim() || board.name); setRenaming(null); }}
              onKeyDown={event => {
                if (event.key === "Enter") event.currentTarget.blur();
                if (event.key === "Escape") { event.currentTarget.value = board.name; event.currentTarget.blur(); }
              }} />
          ) : (
            <button type="button" role="tab" aria-selected={board.id === boardId} onClick={() => setBoard(board.id)}
              onDoubleClick={() => { setBoard(board.id); setRenaming(board.id); }} title={t("Dubbelklicka för att byta namn")}>
              {board.name || t("Tavla")}
              {publishedFor(board.id).map(club => <PublishedIcon key={club} clubName={club || null} />)}
            </button>
          )}
          {board.id === boardId && boards.length > 1 && (
            <button type="button" className="tb-tab-close" aria-label={t("Ta bort {name}", { name: board.name })} onClick={() => remove(board.id, board.name)}>×</button>
          )}
        </span>
      ))}
      <BoardMenu />
    </div>
  );
}

/** The project's name, kind and TeamZone team, under Inställningar. */
export function ProjectFields({ className }: { className: string }) {
  const t = useT();
  const { client } = useAccount();
  const meta = useEditor(state => state.meta);
  const { setMeta } = useEditor.getState();
  const [teams, setTeams] = useState<LeaderTeam[]>([]);
  useEffect(() => {
    client?.schema("api").rpc("list_tournament_leader_teams").then(({ data }) => setTeams((data as LeaderTeam[] | null) ?? []));
  }, [client]);
  if (!meta) return null;
  // Another leader of the team changes the boards; the project itself is the owner's.
  if (meta.access !== "owner") {
    return (
      <>
        <p className="tb-hint">{t("{name} äger projektet. Du kan ändra tavlorna; namn, lag, delning och versioner sköter ägaren.", { name: meta.ownerName?.trim() || t("En annan ledare") })}</p>
        <CopyThisProject />
      </>
    );
  }
  const setAccess = async (leaderAccess: LeaderAccess) => {
    const { error } = await client?.schema("api").rpc("set_tactics_leader_access", { target_project_id: meta.id, access: leaderAccess }) ?? { error: true };
    if (error) { window.alert(t("Det gick inte att ändra. Försök igen.")); return; }
    useEditor.setState(state => state.meta ? { meta: { ...state.meta, leaderAccess } } : {});
  };
  return (
    <>
      <label className="tb-field">{t("Namn")}<input value={meta.name} maxLength={120} onChange={event => setMeta({ name: event.target.value })} /></label>
      <select className={className} value={meta.kind} aria-label={t("Typ")} onChange={event => setMeta({ kind: event.target.value as ProjectKind })}>
          {Object.entries(kindLabels).map(([value, label]) => <option key={value} value={value}>{t(label)}</option>)}
        </select>
        {(teams.length > 0 || meta.teamId) && (
          <select className={className} value={meta.teamId ?? ""} aria-label={t("Lag i TeamZone")}
            onChange={event => {
              const team = teams.find(item => item.team_id === event.target.value);
              setMeta({ teamId: team?.team_id ?? null, teamName: team?.team_name ?? null });
            }}>
            <option value="">{t("Inget lag")}</option>
            {meta.teamId && !teams.some(team => team.team_id === meta.teamId) && <option value={meta.teamId}>{meta.teamName ?? t("Laget")}</option>}
            {teams.map(team => <option key={team.team_id} value={team.team_id}>{team.team_name} · {team.club_name}</option>)}
          </select>
        )}
        {meta.teamId && (
          <label className="tb-field">{t("Lagets andra ledare")}
            <select className={className} value={meta.leaderAccess} onChange={event => void setAccess(event.target.value as LeaderAccess)}>
              <option value="view">{t("kan titta och kopiera")}</option>
              <option value="edit">{t("kan redigera tavlorna")}</option>
            </select>
          </label>
        )}
        <CopyThisProject />
    </>
  );
}

/** The whole project, as it is in the editor now, in a new project of your own that opens in place of this one. */
function CopyThisProject() {
  const t = useT();
  const { client } = useAccount();
  const [busy, setBusy] = useState(false);
  const copy = async () => {
    const { meta, document } = useEditor.getState();
    if (!client || !meta || !document) return;
    setBusy(true);
    const id = await copyProject(client, { name: meta.name, kind: meta.kind, teamId: meta.teamId, document }, t);
    if (!id) { setBusy(false); window.alert(t("Kopian kunde inte skapas. Försök igen.")); return; }
    window.location.href = `/tacticsboard/${id}`;
  };
  return (
    <div className="tb-field">
      <button type="button" className="wt-button secondary small" disabled={busy} onClick={() => void copy()}>{busy ? t("Kopierar…") : t("Kopiera projekt")}</button>
      <span className="tb-hint">{t("Alla tavlor i ett nytt eget projekt. Delningslänkar följer inte med.")}</span>
    </div>
  );
}

export function TopBar({ onPresent }: { onPresent: () => void }) {
  const t = useT();
  const { client } = useAccount();
  const meta = useEditor(state => state.meta);
  const saveState = useEditor(state => state.saveState);
  const canUndo = useEditor(state => state.history.past.length > 0);
  const canRedo = useEditor(state => state.history.future.length > 0);
  const { undo, redo } = useEditor.getState();
  const [sharing, setSharing] = useState(false);
  const [living, setLiving] = useState(false);
  const [versions, setVersions] = useState(false);
  const openSettings = useSettings(state => state.open);
  // Opened from a folder (?mapp=<id>), back goes to the folder.
  const [folderId, setFolderId] = useState<string | null>(null);
  useEffect(() => {
    const id = new URLSearchParams(window.location.search).get("mapp");
    setFolderId(id && /^[0-9a-f-]{36}$/.test(id) ? id : null);
  }, []);
  if (!meta) return null;
  const owner = meta.access === "owner";
  return (
    <header className="tb-top">
      {sharing && <ShareDialog onClose={() => setSharing(false)} onCrop={() => { setSharing(false); useCropping.getState().start(() => setSharing(true)); }} />}
      {living && <LiveDialog onClose={() => setLiving(false)} />}
      {versions && <VersionsDialog onClose={() => setVersions(false)} />}
      <SettingsDialog />
      <div className="tb-top-row">
        <Link href={folderId ? `/tacticsboard/mapp/${folderId}` : "/tacticsboard"} className="tb-back"
          aria-label={folderId ? t("Till mappen") : t("Till projekten")} title={meta.name}>‹</Link>
        <Boards />
        <button type="button" className="tb-icon" onClick={undo} disabled={!canUndo} aria-label={t("Ångra")} title={t("Ångra (Ctrl+Z)")}>↶</button>
        <button type="button" className="tb-icon" onClick={redo} disabled={!canRedo} aria-label={t("Gör om")} title={t("Gör om (Ctrl+Y)")}>↷</button>
        <span className="tb-top-group tb-wide-only">
          <button type="button" className="tb-icon tb-glyph" onClick={onPresent} aria-label={t("Visa i helskärm")} title={t("Visa i helskärm, utan redigering")}><FullscreenIcon /></button>
          <button type="button" className="tb-icon tb-glyph" onClick={() => setVersions(true)} aria-label={t("Versioner")} title={t("Tidigare versioner")}><HistoryIcon /></button>
          <button type="button" className="tb-icon tb-glyph" onClick={() => openSettings()} aria-label={t("Inställningar")} title={t("Inställningar för plan, lag och projekt")}><SettingsIcon /></button>
        </span>
        {owner && <LiveButton onClick={() => setLiving(true)} />}
        <TopBarMore onPresent={onPresent} onLive={owner ? () => setLiving(true) : undefined} onVersions={() => setVersions(true)} onSettings={() => openSettings()} />
        <button type="button" className="tb-icon tb-glyph tb-share" onClick={() => setSharing(true)} aria-label={t("Dela")} title={t("Dela: länk, PDF, video och mer")}><ShareIcon /></button>
        <span className="tb-save" data-state={saveState} role="status">
          {t(saveLabels[saveState])}
          {saveState === "error" && client && <button type="button" className="tb-link" onClick={() => void saveNow(client)}>{t("Försök igen")}</button>}
          {saveState === "conflict" && <button type="button" className="tb-link" onClick={() => window.location.reload()}>{t("Hämta senaste")}</button>}
          {saveState === "conflict" && client && <button type="button" className="tb-link" onClick={() => void saveAsCopy(client).then(done => { if (!done) window.alert(t("Kopian kunde inte sparas. Försök igen.")); })}>{t("Spara mina ändringar som kopia")}</button>}
        </span>
      </div>
    </header>
  );
}
