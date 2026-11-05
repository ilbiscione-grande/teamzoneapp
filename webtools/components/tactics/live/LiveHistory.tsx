"use client";

// The host's earlier live lessons on this project, each opening its summary.
import type { SupabaseClient } from "@supabase/supabase-js";
import { useEffect, useState } from "react";
import { useLanguage } from "../../language";
import { LiveSummary } from "./LiveSummary.tsx";

type Lesson = { id: string; code: string; created_at: string; live: boolean; participant_count: number; question_count: number };

export function LiveHistory({ client, projectId, open, onOpen }: { client: SupabaseClient; projectId: string; open: string | null; onOpen: (id: string | null) => void }) {
  const { t, intl } = useLanguage();
  const [lessons, setLessons] = useState<Lesson[] | null>(null);
  useEffect(() => {
    void client.schema("api").rpc("list_tactics_live_sessions", { target_project_id: projectId }).then(({ data }) => setLessons((data as Lesson[] | null) ?? []));
  }, [client, projectId, open]);
  if (open) return <LiveSummary client={client} sessionId={open} onBack={() => onOpen(null)} />;
  const earlier = (lessons ?? []).filter(lesson => !lesson.live);
  if (earlier.length === 0) return null;
  return (
    <>
      <h3>{t("Tidigare lektioner")}</h3>
      <ul className="tb-live-history">
        {earlier.slice(0, 10).map(lesson => (
          <li key={lesson.id}>
            <button type="button" className="tb-link" onClick={() => onOpen(lesson.id)}>
              {new Date(lesson.created_at).toLocaleString(intl, { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" })}
            </button>
            <span className="tb-hint"> {t("{people} deltagare · {questions} frågor", { people: lesson.participant_count, questions: lesson.question_count })}</span>
          </li>
        ))}
      </ul>
    </>
  );
}
