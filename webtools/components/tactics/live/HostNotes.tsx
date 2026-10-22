"use client";

// The presenter's own notes for the board in hand: points to talk about in
// a live lesson. Kept beside the project, never in its document, so no
// participant or shared link sees them; saved a moment after typing stops.
import type { SupabaseClient } from "@supabase/supabase-js";
import { useEffect, useRef, useState } from "react";
import { create } from "zustand";
import { useAccount } from "../../account";
import { useEditor } from "../store.ts";

type NotesState = { projectId: string | null; notes: Record<string, string>; load: (projectId: string, notes: Record<string, string>) => void };

export const useHostNotes = create<NotesState>(set => ({
  projectId: null,
  notes: {},
  load: (projectId, notes) => set({ projectId, notes }),
}));

const SAVE_AFTER_MS = 800;

export function HostNotes({ compact = false }: { compact?: boolean }) {
  const { client } = useAccount();
  const boardId = useEditor(state => state.boardId);
  const projectId = useHostNotes(state => state.projectId);
  const text = useHostNotes(state => (boardId ? state.notes[boardId] : undefined) ?? "");
  const [status, setStatus] = useState<"" | "saving" | "saved" | "error">("");
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => () => { if (timer.current) clearTimeout(timer.current); }, [boardId]);
  if (!boardId || !projectId || !client) return null;

  const save = async (owner: SupabaseClient, board: string, value: string) => {
    setStatus("saving");
    const { error } = await owner.schema("api").rpc("save_tactics_host_notes", { target_project_id: projectId, target_board_id: board, notes: value });
    setStatus(error ? "error" : "saved");
  };
  const change = (value: string) => {
    useHostNotes.setState(state => ({ notes: { ...state.notes, [boardId]: value } }));
    setStatus("");
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => void save(client, boardId, value), SAVE_AFTER_MS);
  };

  return (
    <details className="tb-host-notes" open>
      <summary>Mina anteckningar <small>syns inte för eleverna</small></summary>
      <textarea rows={compact ? 4 : 6} maxLength={5000} value={text} onChange={event => change(event.target.value)}
        placeholder={"Stolpar för den här tavlan, t.ex.\n- Fråga varför 6:an går ner\n- Visa frame 3 två gånger"} />
      <span className="tb-hint" role="status">{status === "saving" ? "Sparar…" : status === "saved" ? "Sparat" : status === "error" ? "Kunde inte spara" : ""}</span>
    </details>
  );
}
