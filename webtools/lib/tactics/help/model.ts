// The help section's content, in Swedish and English side by side: the
// questions and answers (faq.ts) and the guides through every feature
// (guides-*.ts). Written from what the product does; a question it cannot
// answer for certain points to support instead.

export type Text = { sv: string; en: string };

/** A question and its answer: paragraphs; {email} is support's address. */
export type Question = { id: string; q: Text; a: Text[] };

export type QuestionGroup = { id: string; title: Text; questions: Question[] };

/** A guide's part: a heading, a few words, and steps or points in order. */
export type GuideSection = { title: Text; text?: Text; steps?: Text[]; tip?: Text };

export type Guide = { slug: string; title: Text; summary: Text; sections: GuideSection[] };

export type Locale = "sv" | "en";

export const pick = (text: Text, locale: Locale) => text[locale];
