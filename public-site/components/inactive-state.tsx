import Link from "next/link";
import { PortalFooter, PortalHeader, PortalHero, portalClass } from "./portal";

export function InactiveState({ kind }: { kind: "klubb" | "lag" }) {
  return (
    <main className={portalClass}>
      <PortalHeader />
      <PortalHero kicker="Inte publicerad" title={`Den här ${kind === "klubb" ? "klubben" : "lagsidan"} är inte tillgänglig ännu.`}>
        <p className="pz-lead">TeamZone visar bara information som klubben uttryckligen har valt att publicera.</p>
        <div className="cs-hero-actions"><Link className="cs-button" href="/">Till TeamZone</Link><Link className="cs-button ghost" href="/klubbar">Hitta klubb</Link></div>
      </PortalHero>
      <PortalFooter />
    </main>
  );
}
