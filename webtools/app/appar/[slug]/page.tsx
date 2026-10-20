import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { RequireAccount } from "../../../components/shell";
import { findApp, statusLabel, webtoolApps } from "../../../lib/apps";

type Props = { params: Promise<{ slug: string }> };

export function generateStaticParams() {
  return webtoolApps.map(app => ({ slug: app.slug }));
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const app = findApp((await params).slug);
  return app ? { title: app.name, description: app.tagline } : {};
}

export default async function AppPage({ params }: Props) {
  const app = findApp((await params).slug);
  if (!app) notFound();
  return (
    <>
      <section className="wt-hero compact">
        <div className="wt-wrap wt-app-head">
          <span className="wt-card-mark large" aria-hidden="true">{app.mark}</span>
          <div>
            <p className="wt-kicker">{statusLabel[app.status]}</p>
            <h1>{app.name}</h1>
            <p className="wt-lead">{app.tagline}</p>
          </div>
        </div>
      </section>
      <section className="wt-wrap wt-section wt-app-body">
        <div>
          <p>{app.description}</p>
          <h2>Det här kommer appen att kunna</h2>
          <ul className="wt-features">{app.features.map(feature => <li key={feature}>{feature}</li>)}</ul>
        </div>
        <RequireAccount returnTo={`/appar/${app.slug}`}>
          <section className="wt-panel">
            <h2>{app.status === "planned" ? "Vi bygger appen" : "Öppna appen"}</h2>
            <p>
              {app.status === "planned"
                ? `${app.name} är inte klar än. Den öppnas här med ditt TeamZone-konto när den är det.`
                : `${app.name} öppnas med ditt TeamZone-konto.`}
            </p>
            <Link className="wt-link" href="/">Tillbaka till alla appar</Link>
          </section>
        </RequireAccount>
      </section>
    </>
  );
}
