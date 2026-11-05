"use client";

import { createContext, useContext, useMemo } from "react";
import { intlLocale, localeCookieValue, type Locale } from "../lib/i18n/locale";
import { translator, type Translate } from "../lib/i18n/translate";

type Language = { locale: Locale; intl: string; t: Translate; switchable: boolean };

const swedish: Language = { locale: "sv", intl: intlLocale.sv, t: translator("sv"), switchable: false };
const LanguageContext = createContext<Language>(swedish);

export function LanguageProvider({ locale, switchable, children }: { locale: Locale; switchable: boolean; children: React.ReactNode }) {
  const value = useMemo(() => ({ locale, intl: intlLocale[locale], t: translator(locale), switchable }), [locale, switchable]);
  return <LanguageContext.Provider value={value}>{children}</LanguageContext.Provider>;
}

export const useLanguage = () => useContext(LanguageContext);
export const useT = () => useContext(LanguageContext).t;

/** A translated sentence with one bold part, marked {value}. */
export function Bold({ text, value }: { text: string; value: React.ReactNode }) {
  const [before, after = ""] = text.split("{value}");
  return <>{before}<strong>{value}</strong>{after}</>;
}

/** Names the other language in that language, so it can always be found. */
export function LanguageSwitch() {
  const { locale, switchable } = useLanguage();
  if (!switchable) return null;
  const other: Locale = locale === "sv" ? "en" : "sv";
  const choose = () => {
    document.cookie = localeCookieValue(other, window.location.hostname);
    window.location.reload();
  };
  return <button type="button" className="wt-link-button" lang={other} onClick={choose}>{other === "en" ? "English" : "Svenska"}</button>;
}
