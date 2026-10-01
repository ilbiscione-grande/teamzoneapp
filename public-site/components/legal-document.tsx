import Link from "next/link";
import { PortalFooter, PortalHeader, portalClass } from "./portal";

type LegalSection = Readonly<{
  title: string;
  paragraphs?: readonly string[];
  items?: readonly string[];
}>;

export function LegalDocument({
  eyebrow,
  title,
  version,
  introduction,
  sections,
}: Readonly<{
  eyebrow: string;
  title: string;
  version: string;
  introduction: string;
  sections: readonly LegalSection[];
}>) {
  return (
    <main className={portalClass}>
      <PortalHeader active="legal" />
      <div className="cs-section alt"><div className="legal-page">
      <header className="legal-header">
        <nav className="legal-nav" aria-label="Juridiska dokument">
          <Link href="/villkor">Användarvillkor</Link>
          <Link href="/integritet">Integritetspolicy</Link>
        </nav>
      </header>

      <article className="legal-document">
        <div className="draft-banner" role="note">
          <strong>Juridiskt utkast för teknisk testning</strong>
          <span>Text och placeholderuppgifter måste granskas och ersättas före produktionsbruk.</span>
        </div>
        <p className="eyebrow">{eyebrow}</p>
        <h1>{title}</h1>
        <p className="legal-version">Version {version} · Senast uppdaterad 11 september 2026</p>
        <p className="legal-introduction">{introduction}</p>
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
      <PortalFooter />
    </main>
  );
}
