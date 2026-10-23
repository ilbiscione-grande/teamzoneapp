"use client";

// The latest question's answers on the pitch, in metres: a warm spot for
// each answer (where many stand together it glows), for the host always and
// for participants once shown, and a participant's own marker. While the
// question is open, a participant answers by tapping the pitch.
import type { SupabaseClient } from "@supabase/supabase-js";
import type Konva from "konva";
import { Circle, Group, Rect } from "react-konva";
import { questionError } from "../../../lib/tactics/live-questions.ts";
import { useEditor } from "../store.ts";
import { useDraw } from "./draw-store.ts";
import { latestQuestion, useQuestions } from "./question-store.ts";

const SPOT = { radius: 4, fill: "rgba(239,68,68,0.2)", listening: false, perfectDrawEnabled: false };
const DOT = { radius: 0.55, fill: "#b91c1c", listening: false, perfectDrawEnabled: false };

export function LiveAnswers({ answering }: { answering?: { client: SupabaseClient } }) {
  const boardId = useEditor(state => state.boardId);
  const question = useQuestions(latestQuestion);
  const pen = useDraw(state => state.pen);
  if (!question || question.board_id !== boardId) return null;
  const points = question.points ?? [];
  const canAnswer = answering && question.status === "open" && !pen;

  const answer = async (event: Konva.KonvaEventObject<PointerEvent>) => {
    if (!answering) return;
    const at = event.target.getParent()?.getRelativePointerPosition();
    if (!at) return;
    event.cancelBubble = true;
    const mine = { x: Math.round(at.x * 100) / 100, y: Math.round(at.y * 100) / 100 };
    useQuestions.getState().merge({ ...question, mine });
    const { error } = await answering.client.schema("api").rpc("answer_tactics_live_question", { target_question_id: question.id, answer_x: mine.x, answer_y: mine.y });
    useQuestions.getState().set({ error: error ? questionError(error.message) : "" });
  };

  return (
    <Group>
      {points.map(([x, y], index) => <Circle key={`s${index}`} x={x} y={y} {...SPOT} />)}
      {points.map(([x, y], index) => <Circle key={`d${index}`} x={x} y={y} {...DOT} />)}
      {question.mine && (
        <Group x={question.mine.x} y={question.mine.y} listening={false}>
          <Circle radius={1.4} stroke="#facc15" strokeWidth={0.35} />
          <Circle radius={0.5} fill="#facc15" />
        </Group>
      )}
      {/* While the question is open, a tap anywhere on the pitch answers it; nearly clear, as Konva needs a fill to hit. */}
      {canAnswer && <Rect x={-200} y={-200} width={505} height={468} fill="rgba(0,0,0,0.001)" onPointerDown={event => void answer(event)} />}
    </Group>
  );
}
