"use client";

// Sharing a folder by a link: anyone with it sees the folder's projects and
// plays their boards without an account, as last saved, until the link is
// taken back. A project linked in later shows too.
import { useCallback, useEffect, useState } from "react";
import { useAccount } from "../account";

export function FolderShare({ folderId }: { folderId: string }) {
  const { client } = useAccount();
  const [token, setToken] = useState<string | null | undefined>(undefined);
  const [copied, setCopied] = useState(false);
  const [error, setError] = useState("");

  const load = useCallback(async () => {
    if (!client) return;
    const { data, error: loadError } = await client.schema("api").rpc("get_tactics_folder_share_link", { target_folder_id: folderId });
    if (loadError) { setError("Delningen kunde inte hämtas."); setToken(null); return; }
    setToken((data as string | null) ?? null);
  }, [client, folderId]);
  useEffect(() => { void load(); }, [load]);

  const url = token ? `${window.location.origin}/delad/mapp/${token}` : "";
  const share = async () => {
    if (!client) return;
    const { data, error: shareError } = await client.schema("api").rpc("create_tactics_folder_share_link", { target_folder_id: folderId });
    if (shareError) { setError("Länken kunde inte skapas."); return; }
    setError("");
    setToken(data as string);
  };
  const stop = async () => {
    if (!client || !token || !window.confirm("Sluta dela mappen? Länken slutar fungera.")) return;
    const { error: stopError } = await client.schema("api").rpc("revoke_tactics_folder_share_link", { target_token: token });
    if (stopError) { setError("Delningen kunde inte tas bort."); return; }
    setError("");
    setToken(null);
  };
  const copy = async () => {
    try { await navigator.clipboard.writeText(url); setCopied(true); setTimeout(() => setCopied(false), 2000); } catch { /* the field can be copied by hand */ }
  };

  if (token === undefined) return null;
  return (
    <div className="tb-folder-share">
      {token ? (
        <>
          <label className="tb-field">Länk till mappen
            <input readOnly value={url} onFocus={event => event.target.select()} />
          </label>
          <div className="wt-actions">
            <button type="button" className="wt-button small" onClick={() => void copy()}>{copied ? "Kopierad" : "Kopiera"}</button>
            <a className="wt-button secondary small" href={url} target="_blank" rel="noreferrer">Öppna</a>
            <button type="button" className="wt-button secondary small" onClick={() => void stop()}>Sluta dela</button>
          </div>
          <p className="wt-small">Alla med länken ser mappens projekt och kan spela tavlorna, utan konto. Projekt du lägger till senare syns också.</p>
        </>
      ) : (
        <button type="button" className="wt-button secondary small" onClick={() => void share()}>Dela mappen med en länk</button>
      )}
      {error && <p role="alert" className="wt-error">{error}</p>}
    </div>
  );
}
