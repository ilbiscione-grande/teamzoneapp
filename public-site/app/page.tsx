import { PersonalHomePage } from "../components/personal-home";
import { PortalFooter, PortalHeader, portalClass } from "../components/portal";

export const metadata = {
  title: { absolute: "TeamZone – kallelser, närvaro och klubbsajt för föreningslivet" },
  description: "Kallelser, närvaro, meddelanden och en egen klubbsajt för ledare, spelare och föräldrar. Öppna appen eller följ lag och klubbar.",
};

export default function Page() {
  return (
    <main className={portalClass}><PortalHeader active="home" /><PersonalHomePage /><PortalFooter /></main>
  );
}
