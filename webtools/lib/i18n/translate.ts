// Swedish text is the key: t("Logga in") is Swedish as written and English
// from the dictionary. {name} is filled in from the values. Two meanings of one
// Swedish word are told apart by a mark after a bar: "Pass|verktyg".

import { english } from "./en/index.ts";
import type { Locale } from "./locale.ts";

export type TextValues = Record<string, string | number>;
export type Translate = (text: string, values?: TextValues) => string;

const fill = (text: string, values?: TextValues) => !values
  ? text.split("|")[0]
  : text.split("|")[0].replace(/\{(\w+)\}/g, (whole, name: string) => name in values ? String(values[name]) : whole);

export function translator(locale: Locale): Translate {
  if (locale === "sv") return fill;
  return (text, values) => fill(english[text] ?? text, values);
}

/** For lib functions that build sentences with dates. */
export type Language = { t: Translate; intl: string };
export const swedishLanguage: Language = { t: fill, intl: "sv-SE" };
