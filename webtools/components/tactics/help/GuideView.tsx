// One guide: its parts with text, numbered steps and a tip, and the way to
// the next guide and back to the help page.
import Link from "next/link";
import { guides } from "../../../lib/tactics/help/guides.ts";
import { pick, type Guide, type Locale } from "../../../lib/tactics/help/model.ts";
import { WithEmail } from "./HelpIndex.tsx";
import "./help.css";

export function GuideView({ guide, locale }: { guide: Guide; locale: Locale }) {
  const english = locale === "en";
  const at = guides.findIndex(item => item.slug === guide.slug);
  const next = guides[at + 1] ?? null;
  return (
    <article className="tb-helpcenter tb-guide">
      <p className="tb-helpcenter-lead">{pick(guide.summary, locale)}</p>
      {guide.sections.map((section, index) => (
        <section key={index}>
          <h2>{pick(section.title, locale)}</h2>
          {section.text && <p><WithEmail text={pick(section.text, locale)} /></p>}
          {section.steps && <ol>{section.steps.map((step, stepIndex) => <li key={stepIndex}>{pick(step, locale)}</li>)}</ol>}
          {section.tip && <p className="tb-helpcenter-tip"><strong>{english ? "Tip: " : "Tips: "}</strong>{pick(section.tip, locale)}</p>}
        </section>
      ))}
      <nav className="tb-guide-nav" aria-label={english ? "More help" : "Mer hjälp"}>
        <Link href="/support/tacticsboard">{english ? "← All help" : "← All hjälp"}</Link>
        {next && <Link href={`/support/tacticsboard/${next.slug}`}>{(english ? "Next: " : "Nästa: ") + pick(next.title, locale)} →</Link>}
      </nav>
    </article>
  );
}
