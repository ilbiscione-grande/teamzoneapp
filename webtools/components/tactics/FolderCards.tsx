"use client";

// The folders on the start page: a card each, opened on its own page, and a
// new folder made by name. Projects dragged onto a card are put in it.
import Link from "next/link";
import { useState } from "react";
import type { FolderSummary } from "../../lib/tactics/folders.ts";
import { DRAGGED_PROJECTS, draggedProjects } from "./home/project-drag.ts";

type Props = {
  folders: FolderSummary[] | null;
  error: string;
  create: (name: string) => Promise<FolderSummary | null>;
  onDropProjects?: (folder: FolderSummary, projectIds: string[]) => void;
};

export function FolderCards({ folders, error, create, onDropProjects }: Props) {
  const [adding, setAdding] = useState(false);
  const [name, setName] = useState("");
  const [busy, setBusy] = useState(false);
  // The card a dragged project is over.
  const [over, setOver] = useState<string | null>(null);

  const submit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!name.trim()) return;
    setBusy(true);
    const folder = await create(name);
    setBusy(false);
    if (folder) { setName(""); setAdding(false); }
  };

  const dropHandlers = (folder: FolderSummary) => onDropProjects && {
    onDragOver: (event: React.DragEvent) => {
      if (!event.dataTransfer.types.includes(DRAGGED_PROJECTS)) return;
      event.preventDefault();
      event.dataTransfer.dropEffect = "copy";
      setOver(folder.id);
    },
    onDragLeave: (event: React.DragEvent) => {
      if (!event.currentTarget.contains(event.relatedTarget as Node | null)) setOver(current => current === folder.id ? null : current);
    },
    onDrop: (event: React.DragEvent) => {
      event.preventDefault();
      setOver(null);
      const ids = draggedProjects(event.dataTransfer);
      if (ids.length > 0) onDropProjects(folder, ids);
    },
  };

  return (
    <div className="tb-folders" aria-label="Mappar">
      <div className="tb-folders-head">
        <h3>Mappar</h3>
        {!adding && <button type="button" className="wt-button secondary small" onClick={() => setAdding(true)}>Ny mapp</button>}
      </div>
      {adding && (
        <form className="tb-folder-new" onSubmit={submit}>
          <label className="tb-field">Mappens namn
            <input autoFocus value={name} maxLength={120} placeholder="T.ex. Spelidé 2026" onChange={event => setName(event.target.value)} />
          </label>
          <button type="submit" className="wt-button small" disabled={busy || !name.trim()}>Skapa</button>
          <button type="button" className="wt-button secondary small" onClick={() => { setAdding(false); setName(""); }}>Avbryt</button>
        </form>
      )}
      {error && <p role="alert" className="wt-error">{error}</p>}
      {folders && folders.length === 0 && !adding && (
        <p className="wt-small">Samla projekt som hör ihop i en mapp, till exempel delarna av en spelidé. Samma projekt kan ligga i flera mappar.</p>
      )}
      {folders && folders.length > 0 && (
        <ul className="tb-folder-cards">
          {folders.map(folder => (
            <li key={folder.id} className={over === folder.id ? "drop" : undefined} {...dropHandlers(folder)}>
              <Link href={`/tacticsboard/mapp/${folder.id}`}>
                <strong>{folder.name}</strong>
                <span>{over === folder.id ? "Släpp för att lägga i mappen" : `${folder.project_count} projekt`}</span>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
