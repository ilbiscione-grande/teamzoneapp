import { MatchPool } from "../../components/match-pool";
import { PortalFooter, PortalHeader, portalClass } from "../../components/portal";

export const metadata = {
  title: { absolute: "Matchpoolen – hitta träningsmatcher | TeamZone" },
  description: "För ledare i TeamZone: lägg in en hemmatid eller sök en bortamatch och hitta lag i närheten som söker träningsmatcher.",
  robots: { index: false, follow: false },
};

export default function Page() {
  return (
    <main className={portalClass}><PortalHeader active="matchpool" /><MatchPool /><PortalFooter /></main>
  );
}
