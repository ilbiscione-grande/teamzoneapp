// Enkäter: a team's survey, answered on /enkat/<token> without an account.
// The token is a player's personal link or the survey's open link. The page
// and its server action read and write through the service-only database
// functions (api.public_get_team_survey, api.public_submit_team_survey);
// the database checks the answers again.

export type SurveyQuestion = {
  id: string;
  kind: "text" | "long_text" | "scale" | "single" | "multi";
  label: string;
  required: boolean;
  options?: string[];
  low?: string;
  high?: string;
};

export type SurveyAnswer = string | number | string[];
export type SurveyAnswers = Record<string, SurveyAnswer>;

export type PublicSurvey = {
  kind: "personal" | "open";
  title: string;
  intro: string;
  questions: SurveyQuestion[];
  state: "open" | "closed";
  team_name: string | null;
  club_name: string | null;
  person_name: string | null;
  answers: SurveyAnswers | null;
};

export type SubmitResult = { ok: true } | { ok: false; error: string };

const token = /^[a-f0-9]{32}$/;

export function validSurveyToken(value: unknown): value is string {
  return typeof value === "string" && token.test(value);
}

/** The answers as the database keeps them, or the first question left out. */
export function cleanAnswers(questions: SurveyQuestion[], raw: Record<string, unknown>):
  { answers: SurveyAnswers } | { missing: SurveyQuestion } {
  const answers: SurveyAnswers = {};
  for (const question of questions) {
    const value = raw[question.id];
    if (question.kind === "scale") {
      const number = typeof value === "number" ? value : Number(value);
      if (Number.isInteger(number) && number >= 1 && number <= 5) answers[question.id] = number;
    } else if (question.kind === "single") {
      if (typeof value === "string" && question.options?.includes(value)) answers[question.id] = value;
    } else if (question.kind === "multi") {
      const picked = Array.isArray(value) ? value : [];
      const inOrder = (question.options ?? []).filter(option => picked.includes(option));
      if (inOrder.length) answers[question.id] = inOrder;
    } else if (typeof value === "string" && value.trim()) {
      answers[question.id] = value.trim().slice(0, question.kind === "text" ? 300 : 4000);
    }
    if (question.required && !(question.id in answers)) return { missing: question };
  }
  return { answers };
}

/** What a database refusal means for the one answering. */
export function submitError(message: string): string {
  if (message.includes("answer_required")) return "Svara på alla frågor som är markerade med *.";
  if (message.includes("name_required")) return "Skriv ditt namn.";
  if (message.includes("answer_too_long")) return "Ett av svaren är för långt.";
  if (message.includes("rate_limited")) return "Många svar har skickats härifrån. Försök igen om en stund.";
  return "Svaren kunde inte skickas. Försök igen.";
}

/** "P2012 · IF Eksjö" */
export function surveySender(survey: Pick<PublicSurvey, "team_name" | "club_name">): string {
  return [survey.team_name, survey.club_name].filter(Boolean).join(" · ");
}
