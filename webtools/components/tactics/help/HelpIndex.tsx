"use client";

// The help page: a search over everything, the questions by group (opened
// one at a time, or all that match a search), and the guides as cards. The
// words come in the reader's language from lib/tactics/help.
import Link from "next/link";
import { useMemo, useState } from "react";
import { questionGroups } from "../../../lib/tactics/help/faq.ts";
import { guides } from "../../../lib/tactics/help/guides.ts";
import { pick, type Locale, type Text } from "../../../lib/tactics/help/model.ts";
import { supportEmail, supportReply } from "../../../lib/support";
import "./help.css";

const words = {
  search: { sv: "Sök i hjälpen", en: "Search the help" },
  searchHint: { sv: "T.ex. kvitto, video eller frames", en: "E.g. receipt, video or frames" },
  questions: { sv: "Vanliga frågor", en: "Common questions" },
  guides: { sv: "Guider", en: "Guides" },
  guidesLead: { sv: "Steg för steg genom allt Tacticsboard kan.", en: "Step by step through everything Tacticsboard can do." },
  none: { sv: "Inget i hjälpen matchar sökningen. Mejla oss gärna.", en: "Nothing in the help matches the search. Feel free to e-mail us." },
  contact: { sv: "Hittar du inte svaret?", en: "Can't find the answer?" },
  contactText: { sv: "Mejla {email}. {reply}", en: "E-mail {email}. We reply within two working days." },
} satisfies Record<string, Text>;

/** A paragraph with the support address as a link where {email} is. */
export function WithEmail({ text }: { text: string }) {
  const [before, after] = text.split("{email}");
  if (after === undefined) return <>{text}</>;
  return <>{before}<a href={`mailto:${supportEmail}`}>{supportEmail}</a>{after}</>;
}

const matches = (needle: string, ...texts: string[]) => texts.some(text => text.toLowerCase().includes(needle));

export function HelpIndex({ locale }: { locale: Locale }) {
  const say = (text: Text) => pick(text, locale);
  const [query, setQuery] = useState("");
  const needle = query.trim().toLowerCase();
  const found = useMemo(() => ({
    groups: questionGroups
      .map(group => ({ ...group, questions: group.questions.filter(item => !needle || matches(needle, pick(item.q, locale), ...item.a.map(part => pick(part, locale)))) }))
      .filter(group => group.questions.length > 0),
    guides: guides.filter(guide => !needle || matches(needle, pick(guide.title, locale), pick(guide.summary, locale),
      ...guide.sections.flatMap(section => [section.title, section.text, section.tip, ...(section.steps ?? [])].filter((part): part is Text => !!part).map(part => pick(part, locale))))),
  }), [needle, locale]);
  const nothing = found.groups.length === 0 && found.guides.length === 0;

  return (
    <div className="tb-helpcenter">
      <label className="tb-helpcenter-search">
        <span>{say(words.search)}</span>
        <input type="search" value={query} placeholder={say(words.searchHint)} onChange={event => setQuery(event.target.value)} />
      </label>
      {nothing && <p className="wt-note" role="status"><WithEmail text={say(words.none) + " {email}"} /></p>}

      {found.guides.length > 0 && (
        <section aria-labelledby="tb-helpcenter-guides">
          <h2 id="tb-helpcenter-guides">{say(words.guides)}</h2>
          {!needle && <p className="tb-helpcenter-lead">{say(words.guidesLead)}</p>}
          <ul className="tb-helpcenter-guides">
            {found.guides.map(guide => (
              <li key={guide.slug}>
                <Link href={`/support/tacticsboard/${guide.slug}`}>
                  <strong>{say(guide.title)}</strong>
                  <span>{say(guide.summary)}</span>
                </Link>
              </li>
            ))}
          </ul>
        </section>
      )}

      {found.groups.length > 0 && (
        <section aria-labelledby="tb-helpcenter-questions">
          <h2 id="tb-helpcenter-questions">{say(words.questions)}</h2>
          {found.groups.map(group => (
            <div key={group.id} className="tb-helpcenter-group">
              <h3>{say(group.title)}</h3>
              {group.questions.map(item => (
                <details key={item.id} id={item.id} open={!!needle}>
                  <summary>{say(item.q)}</summary>
                  {item.a.map((part, index) => <p key={index}><WithEmail text={say(part)} /></p>)}
                </details>
              ))}
            </div>
          ))}
        </section>
      )}

      <aside className="wt-panel tb-helpcenter-contact">
        <h2>{say(words.contact)}</h2>
        <p><WithEmail text={say(words.contactText).replace("{reply}", supportReply)} /></p>
      </aside>
    </div>
  );
}
