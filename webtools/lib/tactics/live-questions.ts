// Questions on the pitch in a live lesson: a question as the database hands
// it out (the host gets every answer with its name, a participant only
// their own, and the points once shown), merged as events come in, and the
// refusals in words. Pure, so it can be tested.
export type LiveAnswer = { profile_id: string; name: string; x: number; y: number };

export type LiveQuestion = {
  id: string; board_id: string; frame_index: number; prompt: string; status: "open" | "closed"; revealed: boolean; created_at: string;
  answer_count: number;
  /** The host's view: every answer with its name. */
  answers: LiveAnswer[] | null;
  /** A participant's view: their own answer. */
  mine: { x: number; y: number } | null;
  /** Everyone's points: for the host always, for participants once shown. */
  points: [number, number][] | null;
};

/** A question added or updated; what the new copy does not carry (answers, one's own) is kept. */
export function mergeQuestion(list: LiveQuestion[], incoming: LiveQuestion): LiveQuestion[] {
  const known = list.find(question => question.id === incoming.id);
  const merged: LiveQuestion = known ? {
    ...incoming,
    answers: incoming.answers ?? known.answers,
    mine: incoming.mine ?? known.mine,
    points: incoming.points ?? known.points,
    answer_count: Math.max(incoming.answer_count, known.answers?.length ?? 0),
  } : incoming;
  // Asking a new question closes the open one.
  const rest = list.filter(question => question.id !== incoming.id)
    .map(question => merged.status === "open" && question.status === "open" ? { ...question, status: "closed" as const } : question);
  return [...rest, merged].sort((a, b) => a.created_at.localeCompare(b.created_at));
}

/** A participant's answer arriving at the host: theirs replaced, the points and count with it. */
export function addAnswer(list: LiveQuestion[], questionId: string, answer: LiveAnswer): LiveQuestion[] {
  return list.map(question => {
    if (question.id !== questionId) return question;
    const answers = [...(question.answers ?? []).filter(known => known.profile_id !== answer.profile_id), answer];
    return { ...question, answers, answer_count: answers.length, points: answers.map(known => [known.x, known.y] as [number, number]) };
  });
}

export function questionError(message: string): string {
  if (message.includes("question_closed")) return "Frågan är stängd.";
  if (message.includes("invalid_answer")) return "Tryck på planen för att svara.";
  return "Svaret kunde inte skickas.";
}
