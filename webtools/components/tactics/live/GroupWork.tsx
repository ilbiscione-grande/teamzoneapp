"use client";

// Group work, for the host: how many groups, started on the board and frame
// in hand (each group gets its own copy, the project is not touched). While
// the groups work, an overview of their copies as they change: following a
// group, showing one to everyone, moving someone to another group, the
// time, and saving a group's copy as a new board. Ending it throws the
// copies away and brings everyone back to the host's board.
import type { SupabaseClient } from "@supabase/supabase-js";
import { useEffect, useState } from "react";
import { deadlineFrom, groupCounts, groupError, groupSolution, type HostGroup } from "../../../lib/tactics/live-groups.ts";
import type { LiveSession } from "../../../lib/tactics/live.ts";
import { activeBoard, useEditor } from "../store.ts";
import { useDraw } from "./draw-store.ts";
import { GroupTile, type GroupActions } from "./GroupTile.tsx";
import { GroupTimeControl } from "./GroupTime.tsx";
import { GroupWatch } from "./GroupWatch.tsx";
import { useGroup } from "./group-store.ts";
import { useLive } from "./live-store.ts";
import { useHostGroups } from "./use-host-groups.ts";
import { useT } from "../../language";

export function GroupWork({ client, session }: { client: SupabaseClient; session: LiveSession }) {
  const t = useT();
  const groups = useGroup(state => state.groups);
  const watching = useGroup(state => state.groups.find(group => group.id === state.watching) ?? null);
  const participantCount = useLive(state => state.participants.length);
  const [count, setCount] = useState(2);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const counts = groupCounts(participantCount);
  const active = groups.length > 0;
  useHostGroups(client);

  // The groups after a reload, and again when someone comes or goes (someone new is placed in a group when they come in).
  useEffect(() => {
    void client.schema("api").rpc("list_tactics_live_groups", { target_session_id: session.id }).then(({ data }) => {
      if (!data) return;
      const listed = data as HostGroup[];
      useGroup.getState().set({ groups: listed, deadline: deadlineFrom(listed[0]?.ends_in) });
    });
  }, [client, session.id, participantCount]);

  const run = async (work: () => PromiseLike<{ error: { message: string } | null }>) => {
    setBusy(true); setError("");
    const { error: failure } = await work();
    setBusy(false);
    if (failure) setError(t(groupError(failure.message)));
    return !failure;
  };

  const start = async () => {
    const state = useEditor.getState();
    const board = activeBoard(state);
    if (!board) return;
    let started: HostGroup[] = [];
    const ok = await run(async () => {
      const result = await client.schema("api").rpc("start_tactics_live_groups", {
        target_session_id: session.id, group_count: Math.min(count, counts[counts.length - 1]), target_board: board, target_frame_index: state.frameIndex,
      });
      started = (result.data as HostGroup[] | null) ?? [];
      return result;
    });
    if (!ok) return;
    useGroup.getState().set({ groups: started, watching: null, deadline: null });
    useDraw.getState().set({ floorHolder: null, floorName: null });
    useLive.getState().set({ session: { ...session, floor_holder: null, floor_name: null } });
  };

  const end = async () => {
    if (!await run(() => client.schema("api").rpc("end_tactics_live_groups", { target_session_id: session.id }))) return;
    useGroup.getState().set({ groups: [], watching: null, deadline: null });
    // Everyone back where the host is: the board in hand and the view, as when someone joins.
    const state = useEditor.getState();
    const board = activeBoard(state);
    const send = useLive.getState().send;
    if (board && send && state.boardId) {
      send("board", { board });
      send("view", { boardId: state.boardId, frameIndex: state.frameIndex, playhead: state.playhead, playing: state.playing, speed: state.speed, loop: state.loop, stopAt: state.stopAt });
    }
  };

  const actions: GroupActions = {
    busy,
    watch: groupId => useGroup.getState().set({ watching: groupId }),
    show: groupId => void run(async () => {
      const result = await client.schema("api").rpc("show_tactics_live_group", { target_session_id: session.id, target_group_id: groupId });
      if (!result.error) useGroup.getState().set({ groups: useGroup.getState().groups.map(group => ({ ...group, shown: group.id === groupId })) });
      return result;
    }),
    assign: (profileId, groupId) => void run(async () => {
      const result = await client.schema("api").rpc("assign_tactics_live_group", { target_session_id: session.id, target_profile_id: profileId, target_group_id: groupId });
      if (result.data) useGroup.getState().set({ groups: result.data as HostGroup[] });
      return result;
    }),
    save: groupId => {
      const group = useGroup.getState().groups.find(item => item.id === groupId);
      if (!group) return;
      const name = t("{board} – grupp {number}", { board: group.board.name || t("Tavla"), number: group.number });
      // Last in the project, and the host stays on the board in hand (the participants follow it).
      useEditor.getState().change(document => ({ ...document, boards: [...document.boards, groupSolution(group, name)] }));
    },
  };

  if (!active) {
    return (
      <div className="tb-live-groups">
        <p className="tb-hint">{t("Dela in deltagarna i grupper. Varje grupp får en egen kopia av tavlan som den ser ut nu och ändrar den tillsammans. Ditt projekt ändras inte.")}</p>
        <div className="tb-row">
          <label className="tb-field">{t("Antal grupper")}
            <select value={Math.min(count, counts[counts.length - 1])} onChange={event => setCount(Number(event.target.value))}>
              {counts.map(value => <option key={value} value={value}>{value}</option>)}
            </select>
          </label>
          <button type="button" className="wt-button small" disabled={busy || participantCount === 0} onClick={() => void start()}>{t("Starta grupparbete")}</button>
        </div>
        {participantCount === 0 && <p className="tb-hint">{t("Grupparbete kan startas när någon har gått med.")}</p>}
        {error && <p className="wt-error" role="alert">{error}</p>}
      </div>
    );
  }
  return (
    <div className="tb-live-groups">
      <GroupTimeControl client={client} sessionId={session.id} />
      <ol className="tb-live-group-list">
        {groups.map(group => <GroupTile key={group.id} group={group} groups={groups} actions={actions} />)}
      </ol>
      {error && <p className="wt-error" role="alert">{error}</p>}
      <button type="button" className="wt-button small" disabled={busy} onClick={() => void end()}>{t("Avsluta grupparbete")}</button>
      <p className="tb-hint">{t("Gruppernas kopior försvinner och alla följer din tavla igen.")}</p>
      {watching && <GroupWatch group={watching} groups={groups} actions={actions} onClose={() => useGroup.getState().set({ watching: null })} />}
    </div>
  );
}
