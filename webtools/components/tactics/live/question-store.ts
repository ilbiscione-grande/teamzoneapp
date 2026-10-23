"use client";

// A live lesson's questions in this browser: the latest is the one shown.
// The database tells everyone of a question asked, closed or shown, and
// the host alone of each answer.
import type { RealtimeChannel, SupabaseClient } from "@supabase/supabase-js";
import { create } from "zustand";
import { addAnswer, mergeQuestion, type LiveQuestion } from "../../../lib/tactics/live-questions.ts";

type QuestionState = {
  questions: LiveQuestion[];
  error: string;
  merge: (question: LiveQuestion) => void;
  set: (changes: Partial<Pick<QuestionState, "questions" | "error">>) => void;
};

export const useQuestions = create<QuestionState>((set, get) => ({
  questions: [],
  error: "",
  merge: question => set({ questions: mergeQuestion(get().questions, question) }),
  set: changes => set(changes),
}));

/** The question shown now: the latest one asked. */
export const latestQuestion = (state: { questions: LiveQuestion[] }) => state.questions[state.questions.length - 1] ?? null;

/** Questions asked, closed or shown, on the lesson's channel (everyone). */
export function listenQuestions(channel: RealtimeChannel) {
  channel.on("broadcast", { event: "question" }, ({ payload }) => useQuestions.getState().merge(payload as LiveQuestion));
}

/** Answers, on the host's own topic. */
export function listenAnswers(channel: RealtimeChannel) {
  channel.on("broadcast", { event: "answer" }, ({ payload }) => {
    const { questionId, profileId, name, x, y } = payload as { questionId: string; profileId: string; name: string; x: number; y: number };
    useQuestions.getState().set({ questions: addAnswer(useQuestions.getState().questions, questionId, { profile_id: profileId, name, x, y }) });
  });
}

/** The session's questions so far, as the one asking may see them. */
export async function loadQuestions(client: SupabaseClient, sessionId: string) {
  const { data } = await client.schema("api").rpc("list_tactics_live_questions", { target_session_id: sessionId });
  useQuestions.getState().set({ questions: (data as LiveQuestion[] | null) ?? [] });
}
