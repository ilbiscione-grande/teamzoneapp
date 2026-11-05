"use client";

// After a live lesson, for its host: when it was, who was there, each
// question with its answers on a small pitch, and the chat. Opened when the
// lesson ends, and from the list of earlier lessons.
import type { SupabaseClient } from "@supabase/supabase-js";
import { useEffect, useState } from "react";
import { clockTime, type ChatMessage } from "../../../lib/tactics/live-chat.ts";
import type { LiveQuestion } from "../../../lib/tactics/live-questions.ts";
import { useLanguage, useT } from "../../language";

type Summary = {
  id: string; code: string; created_at: string; ended_at: string | null;
  participants: { name: string; guest: boolean; joined_at: string }[];
  messages: ChatMessage[];
  questions: LiveQuestion[];
};

const day = (iso: string, intl: string) => new Date(iso).toLocaleString(intl, { weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });

/** A question's answers on a pitch drawn in a few lines. */
function AnswerPitch({ points }: { points: [number, number][] }) {
  const t = useT();
  return (
    <svg className="tb-summary-pitch" viewBox="-3 -3 111 74" role="img" aria-label={t("{count} svar på planen", { count: points.length })}>
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
  const { t, intl } = useLanguage();
  const [summary, setSummary] = useState<Summary | null>(null);
  const [error, setError] = useState("");
  useEffect(() => {
    void client.schema("api").rpc("get_tactics_live_summary", { target_session_id: sessionId }).then(({ data, error: loadError }) => {
      if (loadError) setError(t("Sammanfattningen kunde inte hämtas.")); else setSummary(data as Summary);
    });
  }, [client, sessionId]);
  if (error) return <p className="wt-error" role="alert">{error}</p>;
  if (!summary) return <p className="tb-hint">{t("Laddar…")}</p>;
  return (
    <div className="tb-summary">
      <button type="button" className="tb-link" onClick={onBack}>{t("‹ Tillbaka")}</button>
      <h3>{t("Lektionen {when}", { when: day(summary.created_at, intl) })}{summary.ended_at ? `–${clockTime(summary.ended_at, intl)}` : t(" (pågår)")}</h3>
      <p className="tb-hint">{t("Kod {code} · {people} deltagare · {questions} frågor · {messages} meddelanden", { code: summary.code, people: summary.participants.length, questions: summary.questions.length, messages: summary.messages.length })}</p>
      <h3>{t("Deltagare")}</h3>
      {summary.participants.length === 0 ? <p className="tb-hint">{t("Ingen gick med.")}</p> : (
        <p>{summary.participants.map(person => person.name + (person.guest ? t(" (gäst)") : "")).join(", ")}</p>
      )}
      {summary.questions.length > 0 && <h3>{t("Frågor på planen")}</h3>}
      {summary.questions.map(question => (
        <div key={question.id} className="tb-summary-question">
          <strong>{question.prompt}</strong>
          <span className="tb-hint">{t("{count} svar", { count: question.answer_count })}{question.answers?.length ? `: ${question.answers.map(answer => answer.name).join(", ")}` : ""}</span>
          <AnswerPitch points={question.points ?? []} />
        </div>
      ))}
      {summary.messages.length > 0 && <h3>{t("Chatten")}</h3>}
      <ol className="tb-chat-list tb-summary-chat">
        {summary.messages.map(message => (
          <li key={message.id} data-host={message.from_host}>
            <div className="tb-chat-meta"><strong>{message.name}</strong>{message.to_host && <span className="tb-chat-tag">{t("Fråga")}</span>}<time>{clockTime(message.created_at, intl)}</time></div>
            <p>{message.body}</p>
          </li>
        ))}
      </ol>
    </div>
  );
}
