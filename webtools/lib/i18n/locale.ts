// Which language a person sees: their own choice, else their browser's.
// Addresses stay the same in both languages, so a shared link works for all.

export const locales = ["sv", "en"] as const;
export type Locale = (typeof locales)[number];

export const localeCookie = "tz_lang";

/** Dates and numbers follow the language. */
export const intlLocale: Record<Locale, string> = { sv: "sv-SE", en: "en-GB" };

export const isLocale = (value: unknown): value is Locale => locales.includes(value as Locale);

/** The browser's first language we have, and English for everyone else. */
export function browserLocale(acceptLanguage: string | null | undefined): Locale {
  const preferred = (acceptLanguage ?? "")
    .split(",")
    .map((part, index) => {
      const [tag, ...params] = part.trim().toLowerCase().split(";");
      const weight = params.map(param => /^q=([\d.]+)$/.exec(param.trim())?.[1]).find(Boolean);
      return { language: tag.split("-")[0], quality: weight === undefined ? 1 : Number(weight), index };
    })
    .filter(entry => entry.language && entry.quality > 0)
    .sort((a, b) => b.quality - a.quality || a.index - b.index);
  const known = preferred.find(entry => isLocale(entry.language));
  return known ? known.language as Locale : "en";
}

/** While English is unfinished everyone gets Swedish, whatever they chose. */
export function pickLocale(cookie: string | null | undefined, acceptLanguage: string | null | undefined, englishOpen: boolean): Locale {
  if (!englishOpen) return "sv";
  return isLocale(cookie) ? cookie : browserLocale(acceptLanguage);
}

/** Set for the whole domain, so the public site and Webtools agree. */
export function localeCookieValue(locale: Locale, hostname: string): string {
  const shared = hostname === "teamzoneapp.se" || hostname.endsWith(".teamzoneapp.se");
  return `${localeCookie}=${locale}; path=/; max-age=31536000; samesite=lax${shared ? "; domain=.teamzoneapp.se" : ""}`;
}
