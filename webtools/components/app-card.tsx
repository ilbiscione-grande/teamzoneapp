import Link from "next/link";
import type { WebtoolApp } from "../lib/apps";
import { statusLabel } from "../lib/apps";

export function AppCard({ app }: { app: WebtoolApp }) {
  return (
    <Link href={`/appar/${app.slug}`} className="wt-card" data-status={app.status}>
      <span className="wt-card-mark" aria-hidden="true">{app.mark}</span>
      <span className="wt-card-body">
        <span className="wt-card-title">{app.name}</span>
        <span className="wt-card-tagline">{app.tagline}</span>
      </span>
      <span className="wt-tag">{statusLabel[app.status]}</span>
    </Link>
  );
}
