"use client";

// Counts page views and says once a minute that Webtools is open, while
// the tab is visible and someone (not a live-lesson guest) is signed in.
// Where Webtools shares TeamZone's database it also counts the day as
// active in Webtools or Tacticsboard, for the support statistics' apps.
import { usePathname } from "next/navigation";
import { useEffect } from "react";
import { appFor, pagePattern, recordAppActivity, recordPresence, recordUse } from "../lib/usage";
import { useAccount } from "./account";

const PRESENCE_EVERY_MS = 60_000;

export function UsageTracker() {
  const { client, session, accepted, links } = useAccount();
  const pathname = usePathname();
  const counts = Boolean(client && session && accepted && !session.user.is_anonymous);

  useEffect(() => {
    if (!counts || !pathname) return;
    const pattern = pagePattern(pathname);
    recordUse(client, "page", pattern);
    if (!links.tacticsboardOnly) recordAppActivity(client, appFor(pattern));
  }, [counts, client, pathname, links.tacticsboardOnly]);

  useEffect(() => {
    if (!counts) return;
    const say = () => { if (document.visibilityState === "visible") recordPresence(client); };
    say();
    const timer = window.setInterval(say, PRESENCE_EVERY_MS);
    document.addEventListener("visibilitychange", say);
    return () => { window.clearInterval(timer); document.removeEventListener("visibilitychange", say); };
  }, [counts, client]);

  return null;
}
