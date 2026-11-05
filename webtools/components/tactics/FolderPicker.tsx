"use client";

// Which folders a project is in: a tick per folder, and a new folder made
// right here (ticked at once). Saving links the project into the ticked
// folders and takes it out of the others; the project itself stays.
import { useEffect, useState } from "react";
import { toggleFolder, type FolderRef } from "../../lib/tactics/folders.ts";
import { useFolders } from "./use-folders.ts";
import "./share.css";
import { useT } from "../language";

type Props = { projectId: string; projectName: string; current: FolderRef[]; onClose: (changed: boolean) => void };

export function FolderPicker({ projectId, projectName, current, onClose }: Props) {
  const t = useT();
  const { folders, error, create, setProjectFolders } = useFolders();
  const [picked, setPicked] = useState<string[]>(() => current.map(folder => folder.id));
  const [name, setName] = useState("");
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => { if (event.key === "Escape") onClose(false); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  const add = async () => {
    if (!name.trim()) return;
    setBusy(true);
    const folder = await create(name);
    setBusy(false);
    if (folder) { setPicked(ids => toggleFolder(ids, folder.id, true)); setName(""); }
  };

  const save = async (event: React.FormEvent) => {
    event.preventDefault();
    setBusy(true);
    const ok = await setProjectFolders(projectId, picked);
    setBusy(false);
    if (ok) onClose(true);
  };

  return (
    <div className="tb-modal" role="dialog" aria-modal="true" aria-label={t("Mappar")} onClick={event => { if (event.target === event.currentTarget) onClose(false); }}>
      <form className="tb-modal-card" onSubmit={save}>
        <div className="tb-modal-head">
          <h2>{t("Mappar")}</h2>
          <button type="button" className="tb-modal-close" aria-label={t("Stäng")} onClick={() => onClose(false)}>×</button>
        </div>
        <p className="tb-hint">{t("Välj vilka mappar {name} ska ligga i. Projektet länkas in, så en ändring syns i alla mapparna.", { name: projectName })}</p>
        {folders === null ? <p className="wt-status">{t("Laddar…")}</p> : folders.length === 0 ? (
          <p className="tb-empty">{t("Du har inga mappar än. Skapa en nedan.")}</p>
        ) : (
          <div className="tb-folder-picks">
            {folders.map(folder => (
              <label key={folder.id} className="tb-check">
                <input type="checkbox" checked={picked.includes(folder.id)}
                  onChange={event => setPicked(ids => toggleFolder(ids, folder.id, event.target.checked))} />
                {folder.name}
              </label>
            ))}
          </div>
        )}
        <div className="tb-folder-new">
          <label className="tb-field">{t("Ny mapp")}
            <input value={name} maxLength={120} placeholder={t("T.ex. Spelidé 2026")} onChange={event => setName(event.target.value)}
              onKeyDown={event => { if (event.key === "Enter") { event.preventDefault(); void add(); } }} />
          </label>
          <button type="button" className="wt-button secondary small" disabled={busy || !name.trim()} onClick={() => void add()}>{t("Skapa")}</button>
        </div>
        {error && <p className="wt-error" role="alert">{error}</p>}
        <div className="tb-actions">
          <button type="submit" className="wt-button small" disabled={busy || folders === null}>{busy ? t("Sparar…") : t("Spara")}</button>
          <button type="button" className="wt-button secondary small" onClick={() => onClose(false)}>{t("Avbryt")}</button>
        </div>
      </form>
    </div>
  );
}
