import Link from "next/link";
import type { WebtoolApp } from "../lib/apps";
import { statusLabel } from "../lib/apps";

type Props = {
  app: WebtoolApp;
  /** Production: Tacticsboard is open, and the others are shown as coming. */
  tacticsboardOnly?: boolean;
};

export function AppCard({ app, tacticsboardOnly = false }: Props) {
  const tacticsboard = app.slug === "tacticsboard";
  const status = !tacticsboardOnly ? app.status : tacticsboard ? "live" : "planned";
  const content = (
    <>
      <span className="wt-card-mark" aria-hidden="true">{app.mark}</span>
      <span className="wt-card-body">
        <span className="wt-card-title">{app.name}</span>
        <span className="wt-card-tagline">{app.tagline}</span>
      </span>
      <span className="wt-tag">{statusLabel[status]}</span>
    </>
  );
  if (tacticsboardOnly && !tacticsboard) {
    return <div className="wt-card wt-card-coming" data-status={status}>{content}</div>;
  }
  return (
    <Link href={tacticsboard ? "/tacticsboard" : `/appar/${app.slug}`} className="wt-card" data-status={status}>
      {content}
    </Link>
  );
}
