// Production sells Tacticsboard only (WEBTOOLS_SCOPE=tacticsboard): the other
// apps and the start page lead to Tacticsboard, here and in the proxy.

const otherApps = /^\/(bokningar|turnering|turneringar|aviseringar)(\/|$)/;

/** Where a path goes when only Tacticsboard is open, or null if it stays. */
export function tacticsboardOnlyRedirect(path: string): string | null {
  if (path === "/" || otherApps.test(path)) return "/tacticsboard";
  const app = /^\/appar\/([^/]+)\/?$/.exec(path);
  return app && app[1] !== "tacticsboard" ? "/tacticsboard" : null;
}
