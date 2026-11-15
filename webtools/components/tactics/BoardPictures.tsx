"use client";

// Keeps a picture of each board's first frame beside the project, for the
// TeamZone app (lib/tactics/board-picture.ts). A moment after a save, and
// when a project is opened, the boards whose first frame changed since their
// picture was last sent are drawn off screen one at a time and sent together.
// What was sent is remembered in the browser, so a project from before
// pictures gets them once it is opened. Nothing here may stop the save.
import type { SupabaseClient } from "@supabase/supabase-js";
import dynamic from "next/dynamic";
import { useEffect, useRef, useState } from "react";
import { PICTURE_LONG_SIDE, PICTURES_PER_SAVE, pictureData, pictureKey, pictureSize } from "../../lib/tactics/board-picture.ts";
import type { Board } from "../../lib/tactics/model.ts";
import { useEditor } from "./store.ts";

const OffscreenBoard = dynamic(() => import("./export/OffscreenBoard.tsx"), { ssr: false });

const DELAY_MS = 4000;
const sentKey = (projectId: string) => `teamzone:tactics-pictures:${projectId}`;

function readSent(projectId: string): Record<string, string> {
  try { return JSON.parse(localStorage.getItem(sentKey(projectId)) ?? "{}") as Record<string, string>; } catch { return {}; }
}

function writeSent(projectId: string, sent: Record<string, string>) {
  try { localStorage.setItem(sentKey(projectId), JSON.stringify(sent)); } catch { /* storage unavailable: drawn again next time */ }
}

type Job = { board: Board; done: (dataUrl: string) => void };

export function BoardPictures({ client }: { client: SupabaseClient | null }) {
  const saveState = useEditor(state => state.saveState);
  const projectId = useEditor(state => state.meta?.id);
  const revision = useEditor(state => state.meta?.revision);
  const canSave = useEditor(state => !!state.meta && state.meta.access !== "view");
  const [job, setJob] = useState<Job | null>(null);
  const running = useRef(false);

  useEffect(() => {
    if (!client || !projectId || !canSave || saveState !== "saved") return;
    const timer = window.setTimeout(() => void send(client, projectId), DELAY_MS);
    return () => window.clearTimeout(timer);
  }, [client, projectId, revision, canSave, saveState]); // eslint-disable-line react-hooks/exhaustive-deps

  async function send(client: SupabaseClient, projectId: string) {
    if (running.current) return;
    const document = useEditor.getState().document;
    if (!document || useEditor.getState().meta?.id !== projectId) return;
    running.current = true;
    try {
      const sent = readSent(projectId);
      const keys = new Map(document.boards.map(board => [board.id, pictureKey(board, document.branding)]));
      const changed = document.boards.filter(board => board.frames.length > 0 && sent[board.id] !== keys.get(board.id)).slice(0, PICTURES_PER_SAVE);
      if (changed.length === 0) return;
      const pictures = [];
      for (const board of changed) {
        const dataUrl = await new Promise<string>(resolve => setJob({ board, done: resolve }));
        const picture = pictureData(dataUrl);
        if (picture) pictures.push({ board_id: board.id, ...picture, ...pictureSize(board, PICTURE_LONG_SIDE) });
      }
      setJob(null);
      if (pictures.length === 0) return;
      const { error } = await client.schema("api").rpc("save_tactics_board_pictures", { target_project_id: projectId, pictures });
      if (error) return;
      // The boards still in the project, with those just sent as they were drawn.
      const next = Object.fromEntries(Object.entries(sent).filter(([id]) => keys.has(id)));
      for (const picture of pictures) next[picture.board_id] = keys.get(picture.board_id)!;
      writeSent(projectId, next);
    } catch {
      // A picture is a nicety for the app; the project is saved without it.
    } finally {
      setJob(null);
      running.current = false;
    }
  }

  if (!job) return null;
  return <OffscreenBoard board={job.board} objects={job.board.frames[0].objects} onPicture={job.done}
    longSide={PICTURE_LONG_SIDE} sharpness={1} type="image/webp" quality={0.8} />;
}
