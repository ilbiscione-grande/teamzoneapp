"use client";

// The editor: the project is read, then the workspace shows the board
// between the tools and a side panel with the selection's properties, the
// frames and their effects, the objects and the team; or the board alone,
// presented on the whole screen. The board itself loads only in the browser (Konva).
import dynamic from "next/dynamic";
import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { normalizeDocument } from "../../lib/tactics/document.ts";
import type { Project } from "../../lib/tactics/model.ts";
import { useAccount } from "../account";
import { Inspector } from "./panels/Inspector.tsx";
import { ObjectList } from "./panels/ObjectList.tsx";
import { SquadPanel } from "./panels/SquadPanel.tsx";
import { FramesPanel } from "./panels/FramesPanel.tsx";
import { Presenter } from "./Presenter.tsx";
import { QuickMenu } from "./QuickMenu.tsx";
import { HelpDialog } from "./HelpDialog.tsx";
import { ToolHint } from "./ToolHint.tsx";
import { DrillPicker } from "./DrillPicker.tsx";
import { SharedViewer } from "./SharedViewer.tsx";
import { LiveBadge } from "./live/LiveBadge.tsx";
import { LivePanel } from "./live/LivePanel.tsx";
import { LiveStrokes } from "./live/LiveStrokes.tsx";
import { LiveAnswers } from "./live/LiveAnswers.tsx";
import { useHostNotes } from "./live/HostNotes.tsx";
import { useLive } from "./live/live-store.ts";
import { Toolbar } from "./panels/Toolbar.tsx";
import { activeBoard, useEditor } from "./store.ts";
import { TopBar } from "./TopBar.tsx";
import { useAutosave } from "./use-autosave.ts";
import { useLiveHost } from "./live/use-live-host.ts";
import { useShortcuts } from "./use-shortcuts.ts";
import { Timeline } from "./timeline/Timeline.tsx";
import { ErrorBoundary } from "./ErrorBoundary.tsx";
import "./tactics.css";

const BoardStage = dynamic(() => import("./stage/BoardStage.tsx"), { ssr: false, loading: () => <div className="tb-stage" /> });

type Panel = "properties" | "frames" | "objects" | "squad" | "live";

/** The loaded project's workspace. */
export function TacticsWorkspace() {
  const [panel, setPanel] = useState<Panel>("properties");
  const [presenting, setPresenting] = useState(false);
  const [help, setHelp] = useState(false);
  const openHelp = useCallback(() => setHelp(true), []);
  const live = useLive(state => !!state.session);
  // On a phone the board gets the room; the panel opens from its tabs.
  const [panelOpen, setPanelOpen] = useState(() => typeof window === "undefined" || window.innerWidth > 760);
  const board = useEditor(activeBoard);
  const selectionCount = useEditor(state => state.selection.length);
  useShortcuts(!presenting && !help, openHelp);
  // Choosing something shows its properties, unless effects are being chosen
  // for it or it is chosen in the object list (where more can be added).
  useEffect(() => { if (selectionCount > 0) setPanel(current => current === "frames" || current === "objects" ? current : "properties"); }, [selectionCount]);
  if (!board) return null;
  if (presenting) return <Presenter onClose={() => setPresenting(false)} />;
  const tabs: [Panel, React.ReactNode][] = [["properties", selectionCount ? "Egenskaper" : "Tavlan"], ["frames", "Frames"], ["objects", "Objekt"], ["squad", "Lag"]];
  // While a live lesson runs, its chat, hands and settings have a tab first.
  if (live) tabs.unshift(["live", <LiveBadge key="live" label="Live" hands />]);
  return (
    <div className="tb-editor" data-panel={panelOpen}>
      <TopBar onPresent={() => setPresenting(true)} />
      <div className="tb-body">
        <Toolbar homeColor={board.teams.home.color} awayColor={board.teams.away.color} onHelp={openHelp} />
        <div className="tb-center">
          <ErrorBoundary label="Tavlan">
            <BoardStage extra={<><LiveStrokes /><LiveAnswers /></>}
              selectionTools={(box, frame) => <QuickMenu box={box} frame={frame} onProperties={() => { setPanel("properties"); setPanelOpen(true); }} />} />
          </ErrorBoundary>
          <ToolHint />
          <DrillPicker />
          <ErrorBoundary label="Tidslinjen"><Timeline board={board} /></ErrorBoundary>
        </div>
        <aside className="tb-panel" aria-label="Panel">
          <div className="tb-panel-tabs" role="tablist">
            {tabs.map(([value, label]) => (
              <button key={value} type="button" role="tab" aria-selected={panelOpen && panel === value}
                onClick={() => { if (panelOpen && panel === value) setPanelOpen(false); else { setPanel(value); setPanelOpen(true); } }}>{label}</button>
            ))}
          </div>
          {panelOpen && (
            <div className="tb-panel-body">
              <ErrorBoundary key={panel} label="Panelen">
                {panel === "objects" && <ObjectList board={board} onOpen={() => setPanel("properties")} />}
                {panel === "properties" && <Inspector board={board} />}
                {panel === "frames" && <FramesPanel board={board} />}
                {panel === "squad" && <SquadPanel board={board} />}
                {panel === "live" && (live ? <LivePanel /> : <Inspector board={board} />)}
              </ErrorBoundary>
            </div>
          )}
        </aside>
      </div>
      {help && <HelpDialog onClose={() => setHelp(false)} />}
    </div>
  );
}

/** A team's project another leader may watch, not edit: as a shared link shows it, with a copy to make your own. */
function WatchProject({ project }: { project: Project }) {
  const { client } = useAccount();
  const [busy, setBusy] = useState(false);
  const copy = async () => {
    if (!client) return;
    setBusy(true);
    const { data, error } = await client.schema("api").rpc("create_tactics_project", {
      project_name: `${project.name} (kopia)`.slice(0, 120), project_kind: project.kind,
      target_team_id: project.teamzone_team_id, project_document: project.document,
    });
    if (error) { setBusy(false); window.alert("Kopian kunde inte skapas. Försök igen."); return; }
    window.location.href = `/tacticsboard/${(data as { id: string }).id}`;
  };
  const document = normalizeDocument(project.document);
  return (
    <SharedViewer back={{ href: "/tacticsboard", label: "Till projekten" }}
      shared={{ name: project.name, kind: project.kind, updated_at: project.updated_at, team_name: project.team_name, board_id: null, boards: document.boards, branding: document.branding }}
      actions={<button type="button" className="tb-icon tb-me" disabled={busy} onClick={() => void copy()}
        title={`${project.owner_name?.trim() || "En annan ledare"} äger projektet. Gör en egen kopia att ändra i.`}>Gör en kopia</button>} />
  );
}

export function TacticsEditor({ id }: { id: string }) {
  const { client } = useAccount();
  const [error, setError] = useState("");
  const [watching, setWatching] = useState<Project | null>(null);
  const loaded = useEditor(state => state.meta?.id === id);
  useAutosave(client);
  useLiveHost(client);

  useEffect(() => {
    if (!client) return;
    let cancelled = false;
    void client.schema("api").rpc("get_tactics_project", { target_project_id: id }).then(({ data, error: loadError }) => {
      if (cancelled) return;
      if (loadError) { setError("Projektet hittades inte, eller så har du inte tillgång till det."); return; }
      const project = data as Project;
      if (project.access === "view") { setWatching(project); return; }
      useEditor.getState().load(project, normalizeDocument(project.document));
      useHostNotes.getState().load(project.id, (data as { host_notes?: Record<string, string> }).host_notes ?? {});
    });
    return () => { cancelled = true; };
  }, [client, id]);

  if (error) return <div className="wt-wrap wt-section"><p className="wt-error" role="alert">{error}</p><Link className="wt-link" href="/tacticsboard">Till projekten</Link></div>;
  if (watching) return <WatchProject project={watching} />;
  if (!loaded) return <p className="wt-wrap wt-section wt-status">Laddar…</p>;
  return <TacticsWorkspace />;
}
