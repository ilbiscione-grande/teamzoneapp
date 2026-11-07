import type { Locale } from "../lib/i18n/locale";

/** The flag of a language, drawn here because Windows shows no flag emoji. */
export function LanguageFlag({ locale }: { locale: Locale }) {
  return locale === "en" ? (
    <svg className="wt-flag" viewBox="0 0 60 40" width="24" height="16" aria-hidden="true" preserveAspectRatio="xMidYMid slice">
      <rect width="60" height="40" fill="#012169" />
      <path d="M0 0 60 40M60 0 0 40" stroke="#ffffff" strokeWidth="8" />
      <path d="M0 0 60 40M60 0 0 40" stroke="#c8102e" strokeWidth="3" />
      <path d="M30 0v40M0 20h60" stroke="#ffffff" strokeWidth="13" />
      <path d="M30 0v40M0 20h60" stroke="#c8102e" strokeWidth="8" />
    </svg>
  ) : (
    <svg className="wt-flag" viewBox="0 0 16 10" width="24" height="16" aria-hidden="true" preserveAspectRatio="xMidYMid slice">
      <rect width="16" height="10" fill="#006aa7" />
      <path d="M6 0v10M0 5h16" stroke="#fecc00" strokeWidth="2" />
    </svg>
  );
}
