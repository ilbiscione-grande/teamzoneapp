import Link from "next/link";
import { SiteHeader } from "../components/site-header";

export default function NotFound() {
  return <main className="public-page"><SiteHeader /><section className="hero-card"><p className="eyebrow">404</p><h1>Sidan kunde inte hittas.</h1><p className="lead">Kontrollera adressen eller gå tillbaka till TeamZone.</p></section><Link className="back-link" href="/">Till TeamZone</Link></main>;
}
