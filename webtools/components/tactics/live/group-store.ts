"use client";

// Group work in a live lesson, in this browser. A participant in a group
// sees the group's copy of the board in place of the host's. What the host
// sends in the meantime is kept aside and shown once the group work ends,
// so the participant comes back to where the host is. The host keeps the
// list of groups and who is in each.
import type { RealtimeChannel, SupabaseClient } from "@supabase/supabase-js";
import { create } from "zustand";
import { groupBoard, type LiveGroup, type LiveGroupSummary } from "../../../lib/tactics/live-groups.ts";
import { applyBoard, type LiveView } from "../../../lib/tactics/live.ts";
import type { Board } from "../../../lib/tactics/model.ts";
import { useEditor } from "../store.ts";

type GroupState = {
  /** Participating: the group this participant is in, or null. */
  group: LiveGroup | null;
  /** Participating: the host's board the group's copy stands in for, and what the host sent meanwhile. */
  hostBoard: Board | null;
  pendingBoards: Record<string, Board>;
  pendingView: LiveView | null;
  /** Hosting: the groups, empty when there is no group work. */
  groups: LiveGroupSummary[];
  set: (changes: Partial<Omit<GroupState, "set">>) => void;
};

export const useGroup = create<GroupState>(set => ({
  group: null,
  hostBoard: null,
  pendingBoards: {},
  pendingView: null,
  groups: [],
  set: changes => set(changes),
}));

/** Whether this participant works in a group now (the host's events are then kept aside). */
export const inGroup = () => useGroup.getState().group !== null;

/** The group's copy on the board, on the group's frame, standing still. */
function showGroup(group: LiveGroup) {
  const { document } = useEditor.getState();
  if (!document) return;
  useEditor.setState({
    document: applyBoard(document, groupBoard(group.board, group.moves)),
    boardId: group.board_id, frameIndex: group.frame_index, playhead: group.frame_index, playing: false, stopAt: null, selection: [],
  });
}

/** Into the group (or the group's board as the database has it now, again). */
export function enterGroup(group: LiveGroup) {
  // Group work started again on another board: the host's board back first.
  if (useGroup.getState().group && useGroup.getState().group?.board_id !== group.board_id) leaveGroup();
  const state = useGroup.getState();
  const hostBoard = state.group ? state.hostBoard : useEditor.getState().document?.boards.find(board => board.id === group.board_id) ?? null;
  useGroup.getState().set({ group, hostBoard, ...(state.group ? {} : { pendingBoards: {}, pendingView: null }) });
  showGroup(group);
}

/** Out of the group: the group's copy goes and the board is the host's again. The host's latest view, to show where the host is now. */
export function leaveGroup(): LiveView | null {
  const { group, hostBoard, pendingBoards, pendingView } = useGroup.getState();
  if (!group) return null;
  useGroup.getState().set({ group: null, hostBoard: null, pendingBoards: {}, pendingView: null });
  const { document } = useEditor.getState();
  if (!document) return pendingView;
  let next = hostBoard ? applyBoard(document, hostBoard) : document;
  for (const board of Object.values(pendingBoards)) next = applyBoard(next, board);
  useEditor.setState({ document: next });
  return pendingView;
}

/** A board from the host while in a group: kept for later. */
export function keepBoard(board: Board) {
  useGroup.getState().set({ pendingBoards: { ...useGroup.getState().pendingBoards, [board.id]: board } });
}

/** The participant's own group from the database: in, or out when there is none. */
export async function loadGroup(client: SupabaseClient, sessionId: string, onView: (view: LiveView) => void) {
  const { data, error } = await client.schema("api").rpc("get_tactics_live_group", { target_session_id: sessionId });
  if (error) { console.error("tactics live group", error); return; }
  if (data) enterGroup(data as LiveGroup);
  else { const view = leaveGroup(); if (view) onView(view); }
}

/** The lesson's channel says group work started or ended. */
export function listenGroups(channel: RealtimeChannel, client: SupabaseClient, sessionId: string, onView: (view: LiveView) => void) {
  channel.on("broadcast", { event: "groups" }, ({ payload }) => {
    if ((payload as { active: boolean }).active) { void loadGroup(client, sessionId, onView); return; }
    // Out at once, before the host's next view comes in.
    const view = leaveGroup();
    if (view) onView(view);
  });
}
