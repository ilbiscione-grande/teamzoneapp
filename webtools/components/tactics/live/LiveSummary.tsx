"use client";

// After a live lesson, for its host: when it was, who was there, each
// question with its answers on a small pitch, and the chat. Opened when the
// lesson ends, and from the list of earlier lessons.
import type { SupabaseClient } from "@supabase/supabase-js";
import { useEffect, useState } from "react";
import { clockTime, type ChatMessage } from "../../../lib/tactics/live-chat.ts";
import type { LiveQuestion } from "../../../lib/tactics/live-questions.ts";

type Summary = {
  id: string; code: string; created_at: string; ended_at: string | null;
  participants: { name: string; guest: boolean; joined_at: string }[];
  messages: ChatMessage[];
  questions: LiveQuestion[];
};

const day = (iso: string) => new Date(iso).toLocaleString("sv-SE", { weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });

/** A question's answers on a pitch drawn in a few lines. */
function AnswerPitch({ points }: { points: [number, number][] }) {
  return (
    <svg className="tb-summary-pitch" viewBox="-3 -3 111 74" role="img" aria-label={`${points.length} svar på planen`}>
      <rect x="-3" y="-3" width="111" height="74" fill="#2f7d46" />
      <g fill="none" stroke="rgba(255,255,255,0.8)" strokeWidth="0.5">
        <rect x="0" y="0" width="105" height="68" /><line x1="52.5" y1="0" x2="52.5" y2="68" /><circle cx="52.5" cy="34" r="9.15" />
        <rect x="0" y="13.85" width="16.5" height="40.3" /><rect x="88.5" y="13.85" width="16.5" height="40.3" />
      </g>
      {points.map(([x, y], index) => <circle key={`s${index}`} cx={x} cy={y} r="4" fill="rgba(239,68,68,0.25)" />)}
      {points.map(([x, y], index) => <circle key={`d${index}`} cx={x} cy={y} r="0.8" fill="#b91c1c" />)}
    </svg>
  );
}

export function LiveSummary({ client, sessionId, onBack }: { client: SupabaseClient; sessionId: string; onBack: () => void }) {
  const [summary, setSummary] = useState<Summary | null>(null);
  const [error, setError] = useState("");
  useEffect(() => {
    void client.schema("api").rpc("get_tactics_live_summary", { target_session_id: sessionId }).then(({ data, error: loadError }) => {
      if (loadError) setError("Sammanfattningen kunde inte hämtas."); else setSummary(data as Summary);
    });
  }, [client, sessionId]);
  if (error) return <p className="wt-error" role="alert">{error}</p>;
  if (!summary) return <p className="tb-hint">Laddar…</p>;
  return (
    <div className="tb-summary">
      <button type="button" className="tb-link" onClick={onBack}>‹ Tillbaka</button>
      <h3>Lektionen {day(summary.created_at)}{summary.ended_at ? `–${clockTime(summary.ended_at)}` : " (pågår)"}</h3>
      <p className="tb-hint">Kod {summary.code} · {summary.participants.length} deltagare · {summary.questions.length} frågor · {summary.messages.length} meddelanden</p>
      <h3>Deltagare</h3>
      {summary.participants.length === 0 ? <p className="tb-hint">Ingen gick med.</p> : (
        <p>{summary.participants.map(person => person.name + (person.guest ? " (gäst)" : "")).join(", ")}</p>
      )}
      {summary.questions.length > 0 && <h3>Frågor på planen</h3>}
      {summary.questions.map(question => (
        <div key={question.id} className="tb-summary-question">
          <strong>{question.prompt}</strong>
          <span className="tb-hint">{question.answer_count} svar{question.answers?.length ? `: ${question.answers.map(answer => answer.name).join(", ")}` : ""}</span>
          <AnswerPitch points={question.points ?? []} />
        </div>
      ))}
      {summary.messages.length > 0 && <h3>Chatten</h3>}
      <ol className="tb-chat-list tb-summary-chat">
        {summary.messages.map(message => (
          <li key={message.id} data-host={message.from_host}>
            <div className="tb-chat-meta"><strong>{message.name}</strong>{message.to_host && <span className="tb-chat-tag">Fråga</span>}<time>{clockTime(message.created_at)}</time></div>
            <p>{message.body}</p>
          </li>
        ))}
      </ol>
    </div>
  );
}
