"use client";

// Your folders: listed for the library's cards and the folder picker, made
// and given a project's folders here; a folder's own page uses FolderPage.
import { useCallback, useEffect, useState } from "react";
import { folderErrorText, type FolderSummary } from "../../lib/tactics/folders.ts";
import { useAccount } from "../account";
import { useT } from "../language";

export function useFolders() {
  const t = useT();
  const { client } = useAccount();
  const [folders, setFolders] = useState<FolderSummary[] | null>(null);
  const [error, setError] = useState("");

  const reload = useCallback(async () => {
    if (!client) return;
    const { data, error: loadError } = await client.schema("api").rpc("list_my_tactics_folders");
    if (loadError) { setError(t("Mapparna kunde inte hämtas.")); setFolders([]); return; }
    setError("");
    setFolders(data as FolderSummary[]);
  }, [client]);
  useEffect(() => { void reload(); }, [reload]);

  /** A new folder, or null when it could not be made. */
  const create = async (name: string, description = ""): Promise<FolderSummary | null> => {
    if (!client) return null;
    const { data, error: createError } = await client.schema("api").rpc("create_tactics_folder", {
      folder_name: name.trim(), folder_description: description.trim(),
    });
    if (createError) { setError(folderErrorText(createError.message, t("Mappen kunde inte skapas."), t)); return null; }
    void reload();
    return data as FolderSummary;
  };

  /** Puts a project in exactly these folders. */
  const setProjectFolders = async (projectId: string, folderIds: string[]) => {
    if (!client) return false;
    const { error: saveError } = await client.schema("api").rpc("set_tactics_project_folders", {
      target_project_id: projectId, folder_ids: folderIds,
    });
    if (saveError) { setError(folderErrorText(saveError.message, t("Mapparna kunde inte sparas."), t)); return false; }
    void reload();
    return true;
  };

  /** Links a project at the end of a folder. */
  const addProject = async (folderId: string, projectId: string) => {
    if (!client) return false;
    const { error: addError } = await client.schema("api").rpc("add_tactics_folder_project", {
      target_folder_id: folderId, target_project_id: projectId,
    });
    if (addError) { setError(folderErrorText(addError.message, t("Projektet kunde inte läggas i mappen."), t)); return false; }
    return true;
  };

  return { folders, error, reload, create, setProjectFolders, addProject };
}
