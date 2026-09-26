import { SiteHeader } from "../components/site-header";
import { PersonalHomePage } from "../components/personal-home";

export default function Page() {
  return (
    <main className="public-page"><SiteHeader /><PersonalHomePage /></main>
  );
}
