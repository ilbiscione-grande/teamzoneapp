import type { MetadataRoute } from "next";

export default function robots(): MetadataRoute.Robots {
  const origin = new URL(process.env.PUBLIC_ORIGIN ?? "https://teamzoneapp.se").origin;
  return { rules: { userAgent: "*", allow: "/", disallow: ["/api/", "/_next/"] }, sitemap: `${origin}/sitemap.xml` };
}
