import Link from "next/link";
import { notFound } from "next/navigation";
import { GuideView } from "../../../../components/tactics/help/GuideView.tsx";
import { guideBySlug, guides } from "../../../../lib/tactics/help/guides.ts";
import { pick } from "../../../../lib/tactics/help/model.ts";
import { serverLocale } from "../../../../lib/i18n/server";

// One of Tacticsboard's guides, at /support/tacticsboard/<guide>.
export function generateStaticParams() {
  return guides.map(guide => ({ guide: guide.slug }));
}

export async function generateMetadata({ params }: { params: Promise<{ guide: string }> }) {
  const guide = guideBySlug((await params).guide);
  const locale = await serverLocale();
  if (!guide) return {};
  return { title: `${pick(guide.title, locale)} · Tacticsboard`, description: pick(guide.summary, locale), robots: { index: true, follow: true } };
}

export default async function GuidePage({ params }: { params: Promise<{ guide: string }> }) {
  const guide = guideBySlug((await params).guide);
  if (!guide) notFound();
  const locale = await serverLocale();
  return (
    <div className="wt-wrap wt-section bk-page">
      <p className="wt-kicker dark"><Link href="/support/tacticsboard">{locale === "en" ? "Tacticsboard help" : "Hjälp för Tacticsboard"}</Link></p>
      <h1 className="wt-page-title">{pick(guide.title, locale)}</h1>
      <GuideView guide={guide} locale={locale} />
    </div>
  );
}
