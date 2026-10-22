"use client";

// The editor: the project is read, then the workspace shows the board
// between the tools and a side panel with the selection's properties, the
// frames and their effects, the objects and the team; or the board alone,
// presented on the whole screen. The board itself loads only in the browser (Konva).
import dynamic from "next/dynamic";
import Link from "next/link";
import { useEffect, useState } from "react";
import { normalizeDocument } from "../../lib/tactics/document.ts";
import type { Project } from "../../lib/tactics/model.ts";
import { useAccount } from "../account";
import { Inspector } from "./panels/Inspector.tsx";
import { ObjectList } from "./panels/ObjectList.tsx";
import { SquadPanel } from "./panels/SquadPanel.tsx";
import { FramesPanel } from "./panels/FramesPanel.tsx";
import { Presenter } from "./Presenter.tsx";
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

type Panel = "properties" | "frames" | "objects" | "squad";

/** The loaded project's workspace. */
export function TacticsWorkspace() {
  const [panel, setPanel] = useState<Panel>("properties");
  const [presenting, setPresenting] = useState(false);
  // On a phone the board gets the room; the panel opens from its tabs.
  const [panelOpen, setPanelOpen] = useState(() => typeof window === "undefined" || window.innerWidth > 760);
  const board = useEditor(activeBoard);
  const selectionCount = useEditor(state => state.selection.length);
  useShortcuts();
  // Choosing something shows its properties, unless effects are being chosen for it.
  useEffect(() => { if (selectionCount > 0) setPanel(current => current === "frames" ? current : "properties"); }, [selectionCount]);
  if (!board) return null;
  if (presenting) return <Presenter onClose={() => setPresenting(false)} />;
  const tabs: [Panel, string][] = [["properties", selectionCount ? "Egenskaper" : "Tavlan"], ["frames", "Frames"], ["objects", "Objekt"], ["squad", "Lag"]];
  return (
    <div className="tb-editor" data-panel={panelOpen}>
      <TopBar onPresent={() => setPresenting(true)} />
      <div className="tb-body">
        <Toolbar homeColor={board.teams.home.color} awayColor={board.teams.away.color} />
        <div className="tb-center">
          <ErrorBoundary label="Tavlan"><BoardStage /></ErrorBoundary>
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
                {panel === "objects" && <ObjectList board={board} />}
                {panel === "properties" && <Inspector board={board} />}
                {panel === "frames" && <FramesPanel board={board} />}
                {panel === "squad" && <SquadPanel board={board} />}
              </ErrorBoundary>
            </div>
          )}
        </aside>
      </div>
    </div>
  );
}

export function TacticsEditor({ id }: { id: string }) {
  const { client } = useAccount();
  const [error, setError] = useState("");
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
      useEditor.getState().load(project, normalizeDocument(project.document));
    });
    return () => { cancelled = true; };
  }, [client, id]);

  if (error) return <div className="wt-wrap wt-section"><p className="wt-error" role="alert">{error}</p><Link className="wt-link" href="/tacticsboard">Till projekten</Link></div>;
  if (!loaded) return <p className="wt-wrap wt-section wt-status">Laddar…</p>;
  return <TacticsWorkspace />;
}
