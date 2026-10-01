import { PersonalHomePage } from "../components/personal-home";
import { PortalFooter, PortalHeader, portalClass } from "../components/portal";

export default function Page() {
  return (
    <main className={portalClass}><PortalHeader active="home" /><PersonalHomePage /><PortalFooter /></main>
  );
}
