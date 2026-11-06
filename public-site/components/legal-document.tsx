import Link from "next/link";
import { PortalFooter, PortalHeader, englishOpen, portalClass, type Locale } from "./portal";

const links = {
  sv: { label: "Juridiska dokument", terms: ["/villkor", "Användarvillkor"], privacy: ["/integritet", "Integritetspolicy"], tacticsboard: ["/villkor/tacticsboard", "Villkor för Tacticsboard"] },
  en: { label: "Legal documents", terms: ["/en/terms", "Terms of use"], privacy: ["/en/privacy", "Privacy policy"], tacticsboard: ["/en/terms/tacticsboard", "Terms for Tacticsboard"] },
} as const;

type LegalSection = Readonly<{
  title: string;
  paragraphs?: readonly string[];
  items?: readonly string[];
}>;

export function LegalDocument({
  eyebrow,
  title,
  version,
  updated,
  introduction,
  sections,
  counterpart,
  locale = "sv",
}: Readonly<{
  eyebrow: string;
  title: string;
  version: string;
  /** The date the text last changed, in words. */
  updated: string;
  introduction: string;
  sections: readonly LegalSection[];
  /** The same document in the other language. */
  counterpart: string;
  locale?: Locale;
}>) {
  const nav = links[locale];
  const english = locale === "en";
  return (
    <main className={portalClass} lang={locale}>
      <PortalHeader active="legal" locale={locale} />
      <div className="cs-section alt"><div className="legal-page">
      <header className="legal-header">
        <nav className="legal-nav" aria-label={nav.label}>
          {[nav.terms, nav.privacy, nav.tacticsboard].map(([href, label]) => <Link key={href} href={href}>{label}</Link>)}
          {(english || englishOpen()) && <Link href={counterpart} lang={english ? "sv" : "en"}>{english ? "På svenska" : "In English"}</Link>}
        </nav>
      </header>

      <article className="legal-document">
        <p className="eyebrow">{eyebrow}</p>
        <h1>{title}</h1>
        <p className="legal-version">Version {version} · {english ? "Last updated" : "Senast uppdaterad"} {updated}</p>
        <p className="legal-introduction">{introduction}</p>
        {english && <p className="legal-introduction">This is a translation. If it differs from the <Link href={counterpart}>Swedish text</Link>, the Swedish text applies.</p>}
        <div className="legal-sections">
          {sections.map((section) => (
            <section key={section.title}>
              <h2>{section.title}</h2>
              {section.paragraphs?.map((paragraph) => <p key={paragraph}>{paragraph}</p>)}
              {section.items && (
                <ul>
                  {section.items.map((item) => <li key={item}>{item}</li>)}
                </ul>
              )}
            </section>
          ))}
        </div>
      </article>
      </div></div>
      <PortalFooter locale={locale} />
    </main>
  );
}
