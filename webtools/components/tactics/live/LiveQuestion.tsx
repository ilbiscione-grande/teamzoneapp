"use client";

// Asking on the pitch, for the host: a question on the board and frame in
// hand, how many have answered while it is open, then closing it and
// showing the answers to everyone (as points, without names).
import type { SupabaseClient } from "@supabase/supabase-js";
import { useState } from "react";
import type { LiveQuestion as Question } from "../../../lib/tactics/live-questions.ts";
import { useEditor } from "../store.ts";
import { useLive } from "./live-store.ts";
import { latestQuestion, useQuestions } from "./question-store.ts";

export function LiveQuestion({ client, sessionId }: { client: SupabaseClient; sessionId: string }) {
  const question = useQuestions(latestQuestion);
  const participants = useLive(state => state.participants.length);
  const [prompt, setPrompt] = useState("");
  const [error, setError] = useState("");
  const done = (data: unknown, failure: { message: string } | null, message: string) => {
    if (failure) { setError(message); return false; }
    setError("");
    useQuestions.getState().merge(data as Question);
    return true;
  };

  const ask = async (event: React.FormEvent) => {
    event.preventDefault();
    const { boardId, frameIndex } = useEditor.getState();
    if (!prompt.trim() || !boardId) return;
    const { data, error: askError } = await client.schema("api").rpc("ask_tactics_live_question", { target_session_id: sessionId, target_board_id: boardId, target_frame_index: frameIndex, question_prompt: prompt });
    if (done(data, askError, "Frågan kunde inte ställas.")) setPrompt("");
  };
  const close = async (show: boolean) => {
    if (!question) return;
    const { data, error: closeError } = await client.schema("api").rpc("close_tactics_live_question", { target_question_id: question.id, show_answers: show });
    done(data, closeError, "Frågan kunde inte stängas.");
  };

  return (
    <div className="tb-live-question">
      {question?.status === "open" ? (
        <>
          <p className="tb-live-prompt">{question.prompt}</p>
          <p className="tb-hint">{question.answer_count} av {participants} har svarat. Svaren syns bara för dig tills du visar dem.</p>
          <div className="tb-actions">
            <button type="button" className="wt-button small" onClick={() => void close(true)}>Stäng och visa svaren</button>
            <button type="button" className="wt-button secondary small" onClick={() => void close(false)}>Stäng</button>
          </div>
        </>
      ) : (
        <>
          {question && (
            <p className="tb-hint">Senast: {question.prompt} ({question.answer_count} svar{question.revealed ? ", visas för alla" : ""}).
              {!question.revealed && question.answer_count > 0 && <> <button type="button" className="tb-link" onClick={() => void close(true)}>Visa svaren</button></>}
            </p>
          )}
          <form className="tb-chat-form" onSubmit={ask}>
            <input value={prompt} maxLength={200} onChange={event => setPrompt(event.target.value)} aria-label="Fråga på planen" placeholder="T.ex. Var ska 6:an stå när vi tappar bollen?" />
            <button type="submit" className="wt-button small" disabled={!prompt.trim()}>Fråga</button>
          </form>
          <p className="tb-hint">Eleverna svarar genom att trycka på planen, på tavlan och framen du står på.</p>
        </>
      )}
      {error && <p className="wt-error" role="alert">{error}</p>}
    </div>
  );
}
