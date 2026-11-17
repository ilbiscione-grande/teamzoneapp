"use client";

// Group work, for the host: how many groups, started on the board and frame
// in hand (each group gets its own copy, the project is not touched), who
// is in each group, and ending it, which throws the copies away and brings
// everyone back to the host's board.
import type { SupabaseClient } from "@supabase/supabase-js";
import { useEffect, useState } from "react";
import { groupCounts, groupError, type LiveGroupSummary } from "../../../lib/tactics/live-groups.ts";
import type { LiveSession } from "../../../lib/tactics/live.ts";
import { activeBoard, useEditor } from "../store.ts";
import { useDraw } from "./draw-store.ts";
import { useGroup } from "./group-store.ts";
import { useLive } from "./live-store.ts";
import { useT } from "../../language";

export function GroupWork({ client, session }: { client: SupabaseClient; session: LiveSession }) {
  const t = useT();
  const groups = useGroup(state => state.groups);
  const participantCount = useLive(state => state.participants.length);
  const [count, setCount] = useState(2);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const counts = groupCounts(participantCount);
  const active = groups.length > 0;

  // The groups after a reload, and again when someone comes or goes (someone new is placed in a group when they come in).
  useEffect(() => {
    void client.schema("api").rpc("list_tactics_live_groups", { target_session_id: session.id }).then(({ data }) => {
      if (data) useGroup.getState().set({ groups: data as LiveGroupSummary[] });
    });
  }, [client, session.id, participantCount]);

  const start = async () => {
    const state = useEditor.getState();
    const board = activeBoard(state);
    if (!board) return;
    setBusy(true); setError("");
    const { data, error: startError } = await client.schema("api").rpc("start_tactics_live_groups", {
      target_session_id: session.id, group_count: Math.min(count, counts[counts.length - 1]), target_board: board, target_frame_index: state.frameIndex,
    });
    setBusy(false);
    if (startError) { setError(t(groupError(startError.message))); return; }
    useGroup.getState().set({ groups: data as LiveGroupSummary[] });
    useDraw.getState().set({ floorHolder: null, floorName: null });
    useLive.getState().set({ session: { ...session, floor_holder: null, floor_name: null } });
  };

  const end = async () => {
    setBusy(true); setError("");
    const { error: endError } = await client.schema("api").rpc("end_tactics_live_groups", { target_session_id: session.id });
    setBusy(false);
    if (endError) { setError(t(groupError(endError.message))); return; }
    useGroup.getState().set({ groups: [] });
    // Everyone back where the host is: the board in hand and the view, as when someone joins.
    const state = useEditor.getState();
    const board = activeBoard(state);
    const send = useLive.getState().send;
    if (board && send && state.boardId) {
      send("board", { board });
      send("view", { boardId: state.boardId, frameIndex: state.frameIndex, playhead: state.playhead, playing: state.playing, speed: state.speed, loop: state.loop, stopAt: state.stopAt });
    }
  };

  if (!active) {
    return (
      <div className="tb-live-groups">
        <p className="tb-hint">{t("Dela in deltagarna i grupper. Varje grupp får en egen kopia av tavlan som den ser ut nu och flyttar spelarna tillsammans. Ditt projekt ändras inte.")}</p>
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
      <ol className="tb-live-group-list">
        {groups.map(group => (
          <li key={group.id}>
            <strong>{t("Grupp {number}", { number: group.number })}</strong>{" "}
            <span>{group.members.length > 0 ? group.members.map(member => member.name).join(", ") : t("ingen än")}</span>
          </li>
        ))}
      </ol>
      <button type="button" className="wt-button small" disabled={busy} onClick={() => void end()}>{t("Avsluta grupparbete")}</button>
      <p className="tb-hint">{t("Gruppernas kopior försvinner och alla följer din tavla igen.")}</p>
      {error && <p className="wt-error" role="alert">{error}</p>}
    </div>
  );
}
