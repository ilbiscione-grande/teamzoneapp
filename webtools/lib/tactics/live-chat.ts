// A live lesson's chat and raised hands: messages kept in order without
// doubles (a sent message comes back over the channel too), what the
// database's refusals mean to the one writing, and the hands in the order
// they went up.
export type ChatMode = "off" | "on" | "questions";

export type ChatMessage = {
  id: string; profile_id: string; name: string; from_host: boolean; to_host: boolean; body: string; created_at: string;
};

export const chatModeLabels: Record<ChatMode, string> = { on: "På för alla", questions: "Bara frågor till mig", off: "Av" };

const KEEP = 200;

/** The messages with new ones added: each once, oldest first, the latest 200. */
export function mergeMessages(list: ChatMessage[], incoming: ChatMessage[]): ChatMessage[] {
  const byId = new Map(list.map(message => [message.id, message]));
  for (const message of incoming) byId.set(message.id, message);
  return [...byId.values()].sort((a, b) => a.created_at.localeCompare(b.created_at)).slice(-KEEP);
}

export function chatError(message: string): string {
  if (message.includes("chat_off")) return "Läraren har stängt av chatten.";
  if (message.includes("muted")) return "Läraren har stängt av chatten för dig.";
  if (message.includes("too_fast")) return "Vänta en stund innan du skriver igen.";
  if (message.includes("invalid_message")) return "Skriv något, högst 500 tecken.";
  return "Meddelandet kunde inte skickas.";
}

/** Who has a hand up, the first to raise it first. */
export function raisedHands<T extends { hand?: number | null }>(people: T[]): T[] {
  return people.filter(person => person.hand).sort((a, b) => (a.hand ?? 0) - (b.hand ?? 0));
}

/** "14:05" for a message's time. */
export const clockTime = (iso: string) => new Date(iso).toLocaleTimeString("sv-SE", { hour: "2-digit", minute: "2-digit" });
