"use server";

import { headers } from "next/headers";
import { cleanAnswers, submitError, validSurveyToken, type SubmitResult } from "../../../lib/survey";
import { ipHash, loadPublicSurvey, submitPublicSurvey } from "../../../lib/survey-server";

/** Sends the answers. Next checks that the call comes from this site. */
export async function sendSurvey(token: string, name: string, raw: Record<string, unknown>): Promise<SubmitResult> {
  if (!validSurveyToken(token) || !raw || typeof raw !== "object") return { ok: false, error: submitError("") };
  const survey = await loadPublicSurvey(token);
  if (!survey) return { ok: false, error: "Enkäten finns inte längre. Fråga dina ledare." };
  if (survey.state === "closed") return { ok: false, error: "Enkäten är stängd och tar inte emot fler svar." };
  const clean = cleanAnswers(survey.questions, raw);
  if ("missing" in clean) return { ok: false, error: `Svara på frågan: ${clean.missing.label}` };
  const trimmed = typeof name === "string" ? name.trim().replace(/\s+/g, " ").slice(0, 120) : "";
  if (survey.kind === "open" && trimmed.length < 2) return { ok: false, error: submitError("name_required") };
  const result = await submitPublicSurvey(token, survey.kind === "open" ? trimmed : null, clean.answers,
    ipHash((await headers()).get("x-forwarded-for")));
  if (result.accepted) return { ok: true };
  if (result.closed) return { ok: false, error: "Enkäten är stängd och tar inte emot fler svar." };
  if (result.not_found) return { ok: false, error: "Enkäten finns inte längre. Fråga dina ledare." };
  if (result.error) console.error("survey submit", result.error);
  return { ok: false, error: submitError(result.error ?? "") };
}
