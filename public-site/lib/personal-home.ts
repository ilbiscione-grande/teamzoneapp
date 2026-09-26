export type Channel = { kind: "club" | "team"; id: string; name: string; slug: string; club_slug?: string; club_name?: string; locality?: string; age_class?: string };
export type FeedItem = { id: string; kind: "news" | "result"; happened_at: string; title: string; summary?: string; club_slug: string; club_name: string; article_slug?: string; team_slug?: string; team_name?: string; score_us?: number; score_opponent?: number; report_text?: string | null };
export type Cursor = { before_at: string; before_id: string; before_kind: string };
export type PersonalHome = { available: boolean; following: Channel[]; items: FeedItem[]; next_cursor: Cursor | null; unavailable_count: number };
export function channelHref(channel: Channel): string { return channel.kind === "team" ? `/${channel.club_slug}/${channel.slug}` : `/${channel.slug}`; }
export function feedHref(item: FeedItem): string { return item.kind === "news" ? `/${item.club_slug}/nyheter/${item.article_slug}` : `/${item.club_slug}/${item.team_slug}#resultat`; }
export function mergeFeed(previous: FeedItem[], next: FeedItem[]): FeedItem[] {
  return [...new Map([...previous, ...next].map(item => [`${item.kind}:${item.id}`, item])).values()];
}
export function safeReturnPath(value: string | null): string | null {
  return value && /^\/[a-z0-9-]+(?:\/[a-z0-9-]+)?$/.test(value) ? value : null;
}
