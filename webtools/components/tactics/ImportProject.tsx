"use client";

// Importing a project from a file (lib/tactics/transfer.ts): a new project
// of your own with the file's boards, opened at once. Come from a folder
// (?mapp=<id>), it is put in that folder too.
import { useRouter } from "next/navigation";
import { useRef, useState } from "react";
import type { ProjectSummary } from "../../lib/tactics/model.ts";
import { parseImport } from "../../lib/tactics/transfer.ts";
import { useAccount } from "../account";

export function ImportProject({ onCreated }: { onCreated?: (projectId: string) => Promise<unknown> }) {
  const { client } = useAccount();
  const router = useRouter();
  const input = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  const read = async (file: File) => {
    if (!client) return;
    setBusy(true); setError("");
    const parsed = parseImport(await file.text(), file.name);
    if ("error" in parsed) { setBusy(false); setError(parsed.error); return; }
    const { data, error: createError } = await client.schema("api").rpc("create_tactics_project", {
      project_name: parsed.name, project_kind: parsed.kind, target_team_id: null, project_document: parsed.document,
    });
    if (createError) { setBusy(false); setError("Projektet kunde inte skapas. Försök igen."); return; }
    const id = (data as ProjectSummary).id;
    await onCreated?.(id);
    router.push(`/tacticsboard/${id}`);
  };

  return (
    <div className="tb-import">
      <input ref={input} type="file" accept=".json,application/json" hidden
        onChange={event => { const file = event.target.files?.[0]; event.target.value = ""; if (file) void read(file); }} />
      <button type="button" className="wt-button secondary small" disabled={busy} onClick={() => input.current?.click()}>
        {busy ? "Importerar…" : "Importera projekt från fil"}
      </button>
      <span className="wt-small">En fil som exporterats från Tacticsboard (Tavlan → Exportera som fil).</span>
      {error && <p role="alert" className="wt-error">{error}</p>}
    </div>
  );
}
