import { PersonalHomePage } from "../components/personal-home";
import { LaunchLanding } from "../components/launch-landing";
import { PortalFooter, PortalHeader, portalClass, tacticsboardLaunch } from "../components/portal";

export const metadata = {
  title: { absolute: tacticsboardLaunch() ? "TeamZone – Tacticsboard och verktyg för föreningslivet" : "TeamZone – kallelser, närvaro och klubbsajt för föreningslivet" },
  description: "Kallelser, närvaro, meddelanden och en egen klubbsajt för ledare, spelare och föräldrar. Öppna appen eller följ lag och klubbar.",
};

export default function Page() {
  if (tacticsboardLaunch()) return <LaunchLanding />;
  return (
    <main className={portalClass}><PortalHeader active="home" /><PersonalHomePage /><PortalFooter /></main>
  );
}
