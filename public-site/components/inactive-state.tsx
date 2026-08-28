import Link from "next/link";
import { SiteHeader } from "./site-header";

export function InactiveState({ kind }: { kind: "klubb" | "lag" }) {
  return (
    <main className="public-page">
      <SiteHeader />
      <section className="hero-card">
        <p className="eyebrow">Inte publicerad</p>
        <h1>Den här {kind === "klubb" ? "klubben" : "lagsidan"} är inte tillgänglig ännu.</h1>
        <p className="lead">TeamZone visar bara information som klubben uttryckligen har valt att publicera.</p>
      </section>
      <Link className="back-link" href="/">Till TeamZone</Link>
    </main>
  );
}
