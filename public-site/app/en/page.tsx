import { notFound } from "next/navigation";
import { LaunchLanding } from "../../components/launch-landing";
import { tacticsboardLaunch } from "../../components/portal";

export const metadata = {
  title: { absolute: "TeamZone – Tacticsboard and tools for grassroots sport" },
  description: "Draw, animate and present tactics with Tacticsboard. Try it free for 7 days.",
};

export default function EnglishPage() {
  if (!tacticsboardLaunch()) notFound();
  return <LaunchLanding locale="en" />;
}
