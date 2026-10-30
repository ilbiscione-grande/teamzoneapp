"use client";

// The project's earlier versions (lib/tactics/versions.ts): a list, the
// latest first; one chosen shows its boards in small, and can be put back.
// Putting one back keeps the project as it is now as a version first, so
// that can be undone the same way. Only the owner opens this.
import { useEffect, useState } from "react";
import { normalizeDocument } from "../../lib/tactics/document.ts";
import type { Board } from "../../lib/tactics/model.ts";
import { previewOf } from "../../lib/tactics/preview.ts";
import { versionErrorText, versionNote, versionTime, type VersionSummary } from "../../lib/tactics/versions.ts";
import { useAccount } from "../account";
import { useEditor } from "./store.ts";
import { saveNow } from "./use-autosave.ts";

/** A board's first frame in small: the pitch's lines, its players and ball. */
function BoardThumb({ board }: { board: Board }) {
  const preview = previewOf(board);
  const width = 100 * preview.aspect, height = 100;
  return (
    <figure className="tb-version-board">
      <svg viewBox={`0 0 ${width} ${height}`} role="img" aria-label={board.name || "Tavla"}>
        <rect width={width} height={height} rx="3" fill="#2f7d46" />
        {preview.lines.map((line, index) => line.width === 0
          ? <line key={index} x1={line.left * width} y1={line.top * height} x2={line.left * width} y2={(line.top + line.height) * height} stroke="rgba(255,255,255,.8)" strokeWidth="0.8" />
          : line.round
          ? <ellipse key={index} cx={(line.left + line.width / 2) * width} cy={(line.top + line.height / 2) * height} rx={line.width * width / 2} ry={line.height * height / 2} fill="none" stroke="rgba(255,255,255,.8)" strokeWidth="0.8" />
          : <rect key={index} x={line.left * width} y={line.top * height} width={line.width * width} height={line.height * height} fill="none" stroke="rgba(255,255,255,.8)" strokeWidth="0.8" />)}
        {preview.dots.map((dot, index) => (
          <circle key={`d${index}`} cx={dot.left * width} cy={dot.top * height} r={dot.ball ? 1.6 : 2.8} fill={dot.fill} stroke={dot.ball ? "#111827" : "white"} strokeWidth="0.5" />
        ))}
      </svg>
      <figcaption>{board.name || "Tavla"}</figcaption>
    </figure>
  );
}

export function HistoryIcon() {
  return (
    <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M3 12a9 9 0 1 0 3-6.7L3 8" /><path d="M3 3v5h5M12 7v5l3 2" />
    </svg>
  );
}

export function VersionsDialog({ onClose }: { onClose: () => void }) {
  const { client } = useAccount();
  const meta = useEditor(state => state.meta);
  const [versions, setVersions] = useState<VersionSummary[] | null>(null);
  const [chosen, setChosen] = useState<string | null>(null);
  const [boards, setBoards] = useState<Board[] | null>(null);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!client || !meta) return;
    void client.schema("api").rpc("list_tactics_versions", { target_project_id: meta.id }).then(({ data, error: listError }) => {
      if (listError) setError(versionErrorText(listError.message));
      else setVersions((data as VersionSummary[] | null) ?? []);
    });
  }, [client, meta?.id]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!client || !chosen) return;
    setBoards(null);
    let cancelled = false;
    void client.schema("api").rpc("get_tactics_version", { target_version_id: chosen }).then(({ data, error: readError }) => {
      if (cancelled) return;
      if (readError) { setError(versionErrorText(readError.message)); return; }
      setBoards(normalizeDocument((data as { document: unknown }).document).boards);
    });
    return () => { cancelled = true; };
  }, [client, chosen]);

  const restore = async (version: VersionSummary) => {
    if (!client || !meta) return;
    if (!window.confirm(`Återställa versionen från ${versionTime(version.saved_at).toLowerCase()}? Projektet som det är nu sparas som en version först, så du kan ångra.`)) return;
    setBusy(true);
    setError("");
    // What is still unsaved is saved first, so it is in the version kept before the restore.
    if (useEditor.getState().saveState !== "saved") await saveNow(client);
    const state = useEditor.getState();
    if (state.saveState !== "saved" || !state.meta) { setBusy(false); setError("Projektet kunde inte sparas först. Försök igen."); return; }
    const { error: restoreError } = await client.schema("api").rpc("restore_tactics_version", { target_version_id: version.id, expected_revision: state.meta.revision });
    if (restoreError) { setBusy(false); setError(versionErrorText(restoreError.message)); return; }
    window.location.reload();
  };

  const current = versions?.find(version => version.id === chosen);
  return (
    <div className="tb-modal" role="dialog" aria-label="Versioner" onClick={onClose}>
      <div className="tb-modal-card tb-versions" onClick={event => event.stopPropagation()}>
        <div className="tb-modal-head">
          <h2>Versioner</h2>
          <button type="button" className="tb-modal-close" aria-label="Stäng" onClick={onClose}>×</button>
        </div>
        <p className="tb-versions-hint">En version sparas när du börjar redigera, högst en per halvtimme, och när någon annan sparar. De tio senaste finns alltid kvar, äldre i 90 dagar.</p>
        {error && <p className="wt-error" role="alert">{error}</p>}
        {versions === null && !error && <p className="wt-status">Hämtar versioner…</p>}
        {versions?.length === 0 && <p className="wt-status">Inga tidigare versioner än. Den första sparas nästa gång projektet ändras.</p>}
        {versions && versions.length > 0 && (
          <ul className="tb-version-list">
            {versions.map(version => (
              <li key={version.id} data-chosen={version.id === chosen}>
                <button type="button" onClick={() => setChosen(version.id === chosen ? null : version.id)} aria-expanded={version.id === chosen}>
                  <strong>{versionTime(version.saved_at)}</strong>
                  <span>{versionNote(version)}</span>
                </button>
                {version.id === chosen && (
                  <div className="tb-version-detail">
                    {version.name !== meta?.name && <p>Hette <strong>{version.name}</strong></p>}
                    {boards === null ? <p className="wt-status">Hämtar tavlorna…</p> : (
                      <div className="tb-version-boards">{boards.map(board => <BoardThumb key={board.id} board={board} />)}</div>
                    )}
                    {meta?.access === "owner" ? <div className="tb-actions">
                      <button type="button" className="wt-button small" disabled={busy || !current} onClick={() => current && void restore(current)}>
                        {busy ? "Återställer…" : "Återställ den här versionen"}
                      </button>
                    </div> : <p className="tb-hint">Ägaren kan återställa en version.</p>}
                  </div>
                )}
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}
