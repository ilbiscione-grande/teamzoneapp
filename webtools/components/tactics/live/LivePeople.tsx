"use client";

// Who is in a live lesson, for the host: each with a raised hand shown,
// the floor to give or take back, and their chat to turn off or on.
import type { SupabaseClient } from "@supabase/supabase-js";
import type { LiveSession } from "../../../lib/tactics/live.ts";
import { useDraw } from "./draw-store.ts";
import { useLive } from "./live-store.ts";

export function LivePeople({ client, session, onError }: { client: SupabaseClient; session: LiveSession; onError: (message: string) => void }) {
  const participants = useLive(state => state.participants);
  const floorHolder = useDraw(state => state.floorHolder);
  const send = (event: string, payload: object) => useLive.getState().send?.(event, payload);

  const mute = async (key: string, muted: boolean) => {
    const { error } = await client.schema("api").rpc("mute_tactics_live_participant", { target_session_id: session.id, target_profile_id: key, is_muted: muted });
    if (error) { onError("Det gick inte att ändra deltagarens chatt."); return; }
    send("muted", { profileId: key, muted });
  };
  // The database tells everyone who has the floor.
  const floor = async (key: string | null) => {
    const { data, error } = await client.schema("api").rpc("give_tactics_live_floor", { target_session_id: session.id, target_profile_id: key });
    if (error) { onError("Ordet kunde inte ges."); return; }
    const next = data as LiveSession;
    useLive.getState().set({ session: next });
    useDraw.getState().set({ floorHolder: next.floor_holder, floorName: next.floor_name });
  };

  if (participants.length === 0) return <p className="tb-hint">Ingen än.</p>;
  return (
    <ul className="tb-live-people tb-live-people-list">
      {participants.map(person => (
        <li key={person.key} data-floor={person.key === floorHolder}>
          <span>{person.hand ? "✋ " : ""}{person.name}{person.guest && <small> gäst</small>}{person.key === floorHolder && <small> har ordet</small>}</span>
          <span className="tb-live-person-actions">
            <button type="button" className="tb-link" onClick={() => void floor(person.key === floorHolder ? null : person.key)}>
              {person.key === floorHolder ? "Ta tillbaka ordet" : "Ge ordet"}
            </button>
            <button type="button" className="tb-link" onClick={() => void mute(person.key, !person.muted)}>{person.muted ? "Slå på chatten" : "Stäng av chatten"}</button>
          </span>
        </li>
      ))}
    </ul>
  );
}
