import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { InactiveState } from "../../../../components/inactive-state";
import { SiteHeader } from "../../../../components/site-header";
import { canonicalUrl, getClubPage, getPublicArticle } from "../../../../lib/page-data";

export const dynamic = "force-dynamic";
type Props = { params: Promise<{ clubSlug: string; articleSlug: string }> };
type Block = { type: "heading" | "paragraph" | "link"; text: string; href?: string };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { clubSlug, articleSlug } = await params;
  try {
    const article = await getPublicArticle(clubSlug, articleSlug);
    if (article?.not_found) return {};
    if (article?.available === false) return { title: "Nyhet", robots: { index: false, follow: false } };
    const canonical = await canonicalUrl(`/${article.club_slug}/nyheter/${article.slug}`);
    return { title: article.title, description: article.summary, alternates: { canonical }, openGraph: { title: article.title, description: article.summary, type: "article", url: canonical, publishedTime: article.published_at } };
  } catch { return { title: "Nyhet", robots: { index: false, follow: false } }; }
}

export default async function ArticlePage({ params }: Props) {
  try {
    const { clubSlug, articleSlug } = await params;
    const [article, club] = await Promise.all([getPublicArticle(clubSlug, articleSlug), getClubPage(clubSlug)]);
    if (article?.not_found || club?.not_found) notFound();
    if (article?.available === false || club?.available === false) return <InactiveState kind="klubb" />;
    return <main className="public-page"><SiteHeader clubName={club.name} clubHref={`/${clubSlug}`} /><article className="panel article-page"><p className="eyebrow">Nyhet från {club.name}</p><h1>{article.title}</h1><div className="article-byline"><time dateTime={article.published_at}>{formatDate(article.published_at)}</time>{article.author_label && <span>{article.author_label}</span>}</div>{article.summary && <p className="article-lead">{article.summary}</p>}<div className="article-body">{(article.body_blocks as Block[]).map((block, index) => <ContentBlock block={block} key={`${block.type}-${index}`} />)}</div></article><Link className="back-link" href={`/${clubSlug}#nyheter`}>Fler nyheter från {club.name}</Link></main>;
  } catch (error) {
    if ((error as { digest?: string }).digest?.startsWith("NEXT_HTTP_ERROR_FALLBACK;404")) throw error;
    return <InactiveState kind="klubb" />;
  }
}

function ContentBlock({ block }: { block: Block }) {
  if (block.type === "heading") return <h2>{block.text}</h2>;
  if (block.type === "link" && block.href?.startsWith("https://")) return <p><a className="article-link" href={block.href} rel="noopener noreferrer">{block.text}</a></p>;
  return <p>{block.text}</p>;
}
function formatDate(value: string) { return new Intl.DateTimeFormat("sv-SE", { dateStyle: "long", timeStyle: "short" }).format(new Date(value)); }
