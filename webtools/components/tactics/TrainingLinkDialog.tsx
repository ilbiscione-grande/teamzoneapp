"use client";

// Putting the board in one of the team's coming training sessions: the
// sessions of the next weeks to choose from, and the board added last in
// the chosen one as an exercise with its minutes, organisation and coaching
// points, linked so the session shows the board. The project is saved
// first, so the session links what is on the screen.
import { useEffect, useState } from "react";
import { blockFromBoard, blocksWithBoard, hasBoard, type ModuleTraining, type TrainingSession } from "../../lib/tactics/training-link.ts";
import type { Board } from "../../lib/tactics/model.ts";
import { useAccount } from "../account";
import { useEditor } from "./store.ts";
import { saveNow } from "./use-autosave.ts";

const DAY = 24 * 60 * 60 * 1000;
const when = new Intl.DateTimeFormat("sv-SE", { weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });

export function TrainingLinkDialog({ board, onClose }: { board: Board; onClose: () => void }) {
  const { client } = useAccount();
  const meta = useEditor(state => state.meta);
  const [trainings, setTrainings] = useState<ModuleTraining[] | null>(null);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [done, setDone] = useState<ModuleTraining | null>(null);
  const teamId = meta?.teamId ?? null;

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => { if (event.key === "Escape") onClose(); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  useEffect(() => {
    if (!client || !teamId) return;
    let cancelled = false;
    const from = new Date(Date.now() - DAY), to = new Date(Date.now() + 60 * DAY);
    void client.schema("api").rpc("list_module_trainings", { target_team_id: teamId, from_time: from.toISOString(), to_time: to.toISOString() })
      .then(({ data, error: listError }) => {
        if (cancelled) return;
        if (listError) { setError("Lagets träningar kunde inte hämtas. Du behöver kunna planera träningar i laget."); return; }
        setTrainings(((data as ModuleTraining[]) ?? []).filter(item => item.state !== "cancelled"));
      });
    return () => { cancelled = true; };
  }, [client, teamId]);

  const add = async (training: ModuleTraining) => {
    if (!client || !meta) return;
    setBusy(training.event_id);
    setError("");
    await saveNow(client);
    // Saved by someone else meanwhile: read again and try once more.
    for (let attempt = 0; attempt < 2; attempt++) {
      const { data, error: readError } = await client.schema("api").rpc("get_training_session", { target_event_id: training.event_id });
      if (readError || !data) { setError("Träningen kunde inte läsas."); break; }
      const session = data as TrainingSession;
      if (hasBoard(session, meta.id, board.id)) { setDone(training); break; }
      if (session.blocks.length >= 30) { setError("Passet har redan 30 övningar, det är det mesta ett pass kan ha."); break; }
      const { error: saveError } = await client.schema("api").rpc("save_training_session", {
        target_event_id: training.event_id, expected_revision: session.revision, session_theme: session.theme ?? "", session_goal: session.goal ?? "",
        is_published: session.published, session_blocks: blocksWithBoard(session, blockFromBoard(board, meta.id)), session_roster: null,
      });
      if (!saveError) { setDone(training); break; }
      if (!saveError.message.includes("stale_revision") || attempt === 1) { setError("Övningen kunde inte läggas i passet. Försök igen."); break; }
    }
    setBusy(null);
  };

  return (
    <div className="tb-modal" role="dialog" aria-modal="true" aria-label="Lägg i ett träningspass" onClick={event => { if (event.target === event.currentTarget) onClose(); }}>
      <div className="tb-modal-card">
        <div className="tb-modal-head">
          <h2>Lägg i ett träningspass</h2>
          <button type="button" className="tb-modal-close" aria-label="Stäng" onClick={onClose}>×</button>
        </div>
        {done ? (
          <>
            <p>{board.name || "Övningen"} ligger nu sist i passet {done.title || "Träning"}, {when.format(new Date(done.starts_at))}, med tavlan kopplad. Ordningen och resten ändrar du i passet i TeamZone.</p>
            <div className="tb-actions"><button type="button" className="wt-button small" onClick={onClose}>Stäng</button></div>
          </>
        ) : !teamId ? (
          <p>Projektet behöver ett lag. Välj laget under Tavlan, så visas lagets kommande träningar här.</p>
        ) : (
          <>
            <p className="tb-hint">
              Tavlan läggs sist i passet som en övning med minuter, organisation och coachpunkter från övningsfälten. Passet visar tavlan för dem som ser passet.
            </p>
            {error && <p className="wt-error" role="alert">{error}</p>}
            {!trainings && !error && <p className="wt-status">Hämtar lagets träningar…</p>}
            {trainings && trainings.length === 0 && <p>Laget har inga träningar de kommande 60 dagarna.</p>}
            {trainings && trainings.length > 0 && (
              <ul className="tb-trainings">
                {trainings.map(training => (
                  <li key={training.event_id}>
                    <button type="button" disabled={busy !== null} onClick={() => void add(training)}>
                      <strong>{training.title || "Träning"}</strong>
                      <span>{when.format(new Date(training.starts_at))}</span>
                      <small>{training.session === "none" ? "Inget pass ännu" : `${training.blocks} övningar · ${training.minutes} min${training.session === "draft" ? " · utkast" : ""}`}</small>
                      {busy === training.event_id && <small>Lägger till…</small>}
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </>
        )}
      </div>
    </div>
  );
}
