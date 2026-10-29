"use client";

// The folders at the top of Mitt bibliotek: a card each, opened on its own
// page, and a new folder made by name.
import Link from "next/link";
import { useState } from "react";
import type { FolderSummary } from "../../lib/tactics/folders.ts";

type Props = {
  folders: FolderSummary[] | null;
  error: string;
  create: (name: string) => Promise<FolderSummary | null>;
};

export function FolderCards({ folders, error, create }: Props) {
  const [adding, setAdding] = useState(false);
  const [name, setName] = useState("");
  const [busy, setBusy] = useState(false);

  const submit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!name.trim()) return;
    setBusy(true);
    const folder = await create(name);
    setBusy(false);
    if (folder) { setName(""); setAdding(false); }
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
            <li key={folder.id}>
              <Link href={`/tacticsboard/mapp/${folder.id}`}>
                <strong>{folder.name}</strong>
                <span>{folder.project_count} projekt</span>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
