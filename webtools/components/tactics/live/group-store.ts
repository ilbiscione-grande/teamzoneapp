"use client";

// Group work in a live lesson, in this browser. A participant in a group
// sees the group's copy of the board in place of the host's, or, while the
// host shows another group to everyone, that group's copy (to watch). What
// the host sends in the meantime is kept aside and shown once the group
// work ends, so the participant comes back to where the host is. The host
// keeps the groups with their copies, and the one being followed.
import type { RealtimeChannel, SupabaseClient } from "@supabase/supabase-js";
import { create } from "zustand";
import { mergeStrokes, type Stroke } from "../../../lib/tactics/live-draw.ts";
import { deadlineFrom, groupBoard, mergeGroupMoves, type GroupMove, type HostGroup, type LiveGroup } from "../../../lib/tactics/live-groups.ts";
import { applyBoard, applyMoves, type LiveView } from "../../../lib/tactics/live.ts";
import type { Board } from "../../../lib/tactics/model.ts";
import { useEditor } from "../store.ts";
import { useChat } from "./chat-store.ts";
import { useDraw } from "./draw-store.ts";

type GroupState = {
  /** Participating: the group this participant is in, or null. */
  group: LiveGroup | null;
  /** Participating: the group the host shows to everyone, or null. */
  shown: LiveGroup | null;
  /** Participating: the host's board the group's copy stands in for, and what the host sent meanwhile. */
  hostBoard: Board | null;
  pendingBoards: Record<string, Board>;
  pendingView: LiveView | null;
  /** Hosting: the groups with their copies, empty when there is no group work, and the one the host follows. */
  groups: HostGroup[];
  watching: string | null;
  /** Both: when the group work's time runs out, in this browser's clock; null when there is no time set. */
  deadline: number | null;
  set: (changes: Partial<Omit<GroupState, "set">>) => void;
};

export const useGroup = create<GroupState>(set => ({
  group: null,
  shown: null,
  hostBoard: null,
  pendingBoards: {},
  pendingView: null,
  groups: [],
  watching: null,
  deadline: null,
  set: changes => set(changes),
}));

/** Whether this participant works in a group now (the host's events are then kept aside). */
export const inGroup = () => useGroup.getState().group !== null;

/** Another group than one's own, shown to everyone. */
const otherShown = (state: Pick<GroupState, "group" | "shown">) => state.shown !== null && state.shown.id !== state.group?.id;

/** The copy on the participant's board: another group's while it is shown, else their own group's. */
export const displayedGroup = (state: Pick<GroupState, "group" | "shown">) => otherShown(state) ? state.shown : state.group;

/** Whether the participant moves objects on their own group's copy now (not while another group is shown). */
export const worksOnOwn = (state: Pick<GroupState, "group" | "shown">) => state.group !== null && !otherShown(state);

/** The displayed copy on the board, on its frame, standing still. */
function render() {
  const shownGroup = displayedGroup(useGroup.getState());
  const { document } = useEditor.getState();
  if (!shownGroup || !document) return;
  useEditor.setState({
    document: applyBoard(document, groupBoard(shownGroup.board, shownGroup.moves)),
    boardId: shownGroup.board_id, frameIndex: shownGroup.frame_index, playhead: shownGroup.frame_index, playing: false, stopAt: null, selection: [],
  });
}

/** Into the group (or the group's board as the database has it now, again; or another group, moved there by the host). */
export function enterGroup(group: LiveGroup) {
  // Group work started again on another board: the host's board back first.
  if (useGroup.getState().group && useGroup.getState().group?.board_id !== group.board_id) leaveGroup();
  const state = useGroup.getState();
  const hostBoard = state.group ? state.hostBoard : useEditor.getState().document?.boards.find(board => board.id === group.board_id) ?? null;
  useGroup.getState().set({ group, hostBoard, deadline: deadlineFrom(group.ends_in), ...(state.group ? {} : { pendingBoards: {}, pendingView: null }) });
  render();
}

/** The group the host shows to everyone, or none: watched in place of one's own while shown. */
export function setShown(shown: LiveGroup | null) {
  useGroup.getState().set({ shown });
  render();
}

/** Out of the group: the group's copy goes and the board is the host's again. The host's latest view, to show where the host is now. */
export function leaveGroup(): LiveView | null {
  const { group, hostBoard, pendingBoards, pendingView } = useGroup.getState();
  useGroup.getState().set({ shown: null, deadline: null });
  if (!group) return null;
  // The pen out on the group's copy is not out on the class's board.
  useDraw.getState().set({ pen: false });
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

/** The group shown to everyone, from the database. */
export async function loadShown(client: SupabaseClient, sessionId: string) {
  const { data, error } = await client.schema("api").rpc("get_tactics_live_shown_group", { target_session_id: sessionId });
  if (error) { console.error("tactics live shown group", error); return; }
  if (inGroup()) setShown((data as LiveGroup | null) ?? null);
}

/** Both, once the lesson's channel is open (after a reload or coming in late). */
export async function loadGroups(client: SupabaseClient, sessionId: string, onView: (view: LiveView) => void) {
  await loadGroup(client, sessionId, onView);
  await loadShown(client, sessionId);
}

/** The lesson's channel: group work started or ended, someone moved to another group, a group shown to everyone and its moves. */
export function listenGroups(channel: RealtimeChannel, client: SupabaseClient, sessionId: string, onView: (view: LiveView) => void) {
  channel.on("broadcast", { event: "groups" }, ({ payload }) => {
    if ((payload as { active: boolean }).active) { void loadGroup(client, sessionId, onView); return; }
    // Out at once, before the host's next view comes in.
    const view = leaveGroup();
    if (view) onView(view);
  });
  channel.on("broadcast", { event: "group-assigned" }, ({ payload }) => {
    const { profileId, groupId } = payload as { profileId: string; groupId: string };
    const { group } = useGroup.getState();
    // Moved oneself, or someone came to or left one's group (who is in it changes).
    if (profileId === useChat.getState().selfId || group?.id === groupId || group?.members.some(member => member.profile_id === profileId)) {
      void loadGroup(client, sessionId, onView);
    }
  });
  channel.on("broadcast", { event: "groups-timer" }, ({ payload }) => useGroup.getState().set({ deadline: deadlineFrom((payload as { seconds: number | null }).seconds) }));
  channel.on("broadcast", { event: "shown-stroke" }, ({ payload }) => {
    const stroke = payload as Stroke & { group_id: string };
    const state = useGroup.getState();
    if (state.shown && state.shown.id === stroke.group_id && otherShown(state)) state.set({ shown: { ...state.shown, strokes: mergeStrokes(state.shown.strokes, [stroke]) } });
  });
  channel.on("broadcast", { event: "group-shown" }, () => void loadShown(client, sessionId));
  channel.on("broadcast", { event: "shown-move" }, ({ payload }) => {
    const move = payload as GroupMove;
    const state = useGroup.getState();
    // One's own group's moves come on the group's channel.
    if (!state.shown || state.shown.id !== move.groupId || !otherShown(state)) return;
    if (move.dropped) state.set({ shown: { ...state.shown, moves: mergeGroupMoves(state.shown.moves, move.frameIndex, move.moves) } });
    const { document } = useEditor.getState();
    if (document) useEditor.setState({ document: applyMoves(document, move) });
  });
}
