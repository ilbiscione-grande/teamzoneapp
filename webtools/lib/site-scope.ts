// Production sells Tacticsboard only (WEBTOOLS_SCOPE=tacticsboard): the start
// page shows the other apps as coming, and their pages lead back to it.

const otherApps = /^\/(bokningar|turnering|turneringar|aviseringar)(\/|$)/;

export const tacticsboardOnly = () => process.env.WEBTOOLS_SCOPE === "tacticsboard";

/** Where a path goes when only Tacticsboard is open, or null if it stays. */
export function tacticsboardOnlyRedirect(path: string): string | null {
  if (otherApps.test(path)) return "/";
  const app = /^\/appar\/([^/]+)\/?$/.exec(path);
  return app && app[1] !== "tacticsboard" ? "/" : null;
}
