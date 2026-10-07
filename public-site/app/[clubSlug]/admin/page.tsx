import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { AdminApp } from "../../../components/admin/admin-app";
import { ClubHeader, ClubTheme, clubSiteClass } from "../../../components/club-site";
import { getClubPage } from "../../../lib/page-data";

export const dynamic = "force-dynamic";
type Props = { params: Promise<{ clubSlug: string }> };

// Never indexed: the page holds no data itself, everything is loaded after
// sign-in and checked by the server.
export const metadata: Metadata = { title: "Hantera sidan", robots: { index: false, follow: false } };

type ClubSummary = { name?: string; slug?: string; profile_media_path?: string | null; primary_color?: string | null; accent_color?: string | null };

export default async function ClubAdminPage({ params }: Props) {
  const { clubSlug } = await params;
  if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(clubSlug)) notFound();
  // An unpublished club has no public page but must still be administrable,
  // so a missing page is not a 404 here; sign-in decides access.
  let club: ClubSummary | null = null;
  try {
    const page = await getClubPage(clubSlug);
    if (page && !page.not_found && page.available !== false) club = page as ClubSummary;
  } catch { club = null; }
  const name = club?.name ?? clubSlug;
  return <main className={clubSiteClass(club ?? {})}>
    {club && <ClubTheme club={club} />}
    <ClubHeader clubName={name} clubHref={`/${clubSlug}`} crest={club?.profile_media_path}>
      <a href={`/${clubSlug}`}>Till sidan</a>
    </ClubHeader>
    <AdminApp clubSlug={clubSlug} clubName={name} />
  </main>;
}
