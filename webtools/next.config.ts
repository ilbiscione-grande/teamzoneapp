import type { NextConfig } from "next";

// Webtools signs in against TeamZone's Supabase from the browser; nothing
// else may be reached from the page.
const accountApiOrigin = process.env.SUPABASE_URL && /^https:\/\/[a-z0-9]+\.supabase\.co$/.test(process.env.SUPABASE_URL)
  ? process.env.SUPABASE_URL : "";

const securityHeaders = [
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  { key: "X-Frame-Options", value: "DENY" },
  { key: "Strict-Transport-Security", value: "max-age=31536000; includeSubDomains" },
  { key: "Cross-Origin-Opener-Policy", value: "same-origin" },
  { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
  {
    key: "Content-Security-Policy",
    // Development needs eval for React's debugging; production never does.
    value: `default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'; object-src 'none'; script-src 'self' 'unsafe-inline'${process.env.NODE_ENV === "production" ? "" : " 'unsafe-eval'"}; connect-src 'self' ${accountApiOrigin}${process.env.NODE_ENV === "production" ? "" : " ws:"}`,
  },
];

const nextConfig: NextConfig = {
  poweredByHeader: false,
  async headers() {
    return [
      { source: "/:path*", headers: securityHeaders },
      { source: "/api/:path*", headers: [{ key: "Cache-Control", value: "no-store" }] },
    ];
  },
};

export default nextConfig;
