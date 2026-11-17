"use client";

// A participant editing their group's copy (group work step 4): what they
// place, change and remove with the editor's tools is sent to the group a
// moment after, per object, from what the board has beyond the copy as last
// synced. A change that does not reach the group says so, and the copy is
// read again from the database, so nobody works on a copy the others lack.
// The keys: remove the selection, copy it (Ctrl D), Escape back to
// selecting. No undo: it would take back the others' changes too.
import type { SupabaseClient } from "@supabase/supabase-js";
import { useEffect } from "react";
import { boardEdits, mergeGroupEdits, splitEdit } from "../../../lib/tactics/live-group-edits.ts";
import { groupError } from "../../../lib/tactics/live-groups.ts";
import { useEditor } from "../store.ts";
import { useDraw } from "./draw-store.ts";
import { reloadGroup, useGroup } from "./group-store.ts";

const DELAY_MS = 150;

export function useGroupEdits(client: SupabaseClient, sessionId: string, active: boolean) {
  useEffect(() => {
    if (!active) return;
    let timer: number | null = null;
    const flush = () => {
      timer = null;
      const { synced } = useGroup.getState();
      const board = useEditor.getState().document?.boards.find(item => item.id === synced?.id);
      if (!synced || !board || board === synced) return;
      const edits = boardEdits(synced, board).flatMap(splitEdit);
      useGroup.getState().set({ synced: board });
      for (const edit of edits) {
        void client.schema("api").rpc("edit_tactics_live_group", {
          target_session_id: sessionId, target_frame_index: edit.frameIndex, changed_objects: edit.objects, removed_ids: edit.removed,
        }).then(({ error }) => {
          if (error) {
            useDraw.getState().set({ error: groupError(error.message) });
            void reloadGroup(client, sessionId);
            return;
          }
          const { group } = useGroup.getState();
          if (group) useGroup.getState().set({ group: { ...group, edits: mergeGroupEdits(group.edits, edit) } });
        });
      }
    };
    const unsubscribe = useEditor.subscribe((state, before) => {
      if (state.document !== before.document && timer === null) timer = window.setTimeout(flush, DELAY_MS);
    });
    const onKey = (event: KeyboardEvent) => {
      if (event.defaultPrevented) return;
      const target = event.target as HTMLElement | null;
      if (target && (target.tagName === "INPUT" || target.tagName === "TEXTAREA" || target.tagName === "SELECT" || target.isContentEditable)) return;
      const state = useEditor.getState();
      const command = event.ctrlKey || event.metaKey;
      if ((event.key === "Delete" || event.key === "Backspace") && state.selection.length) {
        event.preventDefault();
        state.removeSelected(false);
      } else if (command && event.key.toLowerCase() === "d" && state.selection.length) {
        event.preventDefault();
        state.duplicateSelected();
      } else if (event.key === "Escape") {
        state.setTool("select");
        state.select([]);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => {
      unsubscribe();
      window.removeEventListener("keydown", onKey);
      if (timer !== null) { window.clearTimeout(timer); flush(); }
    };
  }, [client, sessionId, active]);
}
