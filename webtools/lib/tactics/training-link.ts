// A board put in a TeamZone training session as an exercise: the session's
// exercises as the app reads and saves them (api.get_training_session,
// api.save_training_session), with one more at the end that links the
// board. The session is saved whole, as the app does, so the exercises
// already there go back as they came.
import { emptyExercise } from "./library.ts";
import type { Board } from "./model.ts";

/** An upcoming training of the team (api.list_module_trainings). */
export type ModuleTraining = { event_id: string; title: string; starts_at: string; state: string; session: "none" | "draft" | "published"; minutes: number; blocks: number };

type BoardLink = { source: "mine"; ref: string; board_id: string; name: string };

/** An exercise as the session holds it; what the app sends is kept as it is. */
export type TrainingBlock = {
  part: string; title: string; minutes: number; organisation: string; coaching_points: string; phase: string | null;
  source_kind: string; source_id: string | null; players: unknown[]; board: BoardLink | null;
};

export type TrainingSession = { event_id: string; revision: number; published: boolean; theme: string; goal: string; blocks: TrainingBlock[] };

/** The board as an exercise linked to it, its details from the board (a training project's exercise fields). */
export function blockFromBoard(board: Board, projectId: string): TrainingBlock {
  const details = { ...emptyExercise, ...board.exercise };
  const title = (board.name.trim() || "Övning").slice(0, 120);
  return {
    part: details.part, title, minutes: Math.max(0, Math.min(240, Math.round(details.minutes || 0))),
    organisation: (board.description ?? "").slice(0, 2000), coaching_points: details.coachingPoints.slice(0, 2000),
    phase: details.phase, source_kind: "own", source_id: null, players: [],
    board: { source: "mine", ref: projectId, board_id: board.id, name: title },
  };
}

/** The exercises to save: the session's as they are, the board's last. */
export function blocksWithBoard(session: TrainingSession, block: TrainingBlock): TrainingBlock[] {
  const kept = session.blocks.map(item => ({
    part: item.part, title: item.title, minutes: item.minutes, organisation: item.organisation ?? "", coaching_points: item.coaching_points ?? "",
    phase: item.phase ?? null, source_kind: item.source_kind ?? "own", source_id: item.source_id ?? null, players: item.players ?? [], board: item.board ?? null,
  }));
  return [...kept, block];
}

/** Whether the session already has this board as an exercise. */
export const hasBoard = (session: TrainingSession, projectId: string, boardId: string) =>
  session.blocks.some(item => item.board?.source === "mine" && item.board.ref === projectId && item.board.board_id === boardId);
