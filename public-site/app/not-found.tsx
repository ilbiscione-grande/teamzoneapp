import Link from "next/link";
import { PortalFooter, PortalHeader, PortalHero, portalClass } from "../components/portal";

export default function NotFound() {
  return <main className={portalClass}><PortalHeader /><PortalHero kicker="404" title="Sidan kunde inte hittas." mark="404"><p className="pz-lead">Kontrollera adressen eller gå tillbaka till TeamZone.</p><div className="cs-hero-actions"><Link className="cs-button" href="/">Till TeamZone</Link><Link className="cs-button ghost" href="/klubbar">Hitta klubb</Link></div></PortalHero><PortalFooter /></main>;
}
