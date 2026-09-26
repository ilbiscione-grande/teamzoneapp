// Local server routing only. Database publication gates still apply.
export function isLocalPublicView(host: string | null, environment = process.env): boolean {
  return environment.NODE_ENV === "development"
    && environment.TEAMZONE_LOCAL_PUBLIC_VIEW === "1"
    && (host === "localhost:5001" || host === "[::1]:5001" || host === "127.0.0.1:5001");
}
