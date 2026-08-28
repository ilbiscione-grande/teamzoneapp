const base = new URL(process.argv[2] ?? "");
if (base.protocol !== "https:" && base.hostname !== "localhost") throw new Error("Usage: npm run smoke -- https://host");

async function check(path, expectedStatus, assertions = []) {
  const response = await fetch(new URL(path, base), { redirect: "manual" });
  if (response.status !== expectedStatus) throw new Error(`${path}: expected ${expectedStatus}, got ${response.status}`);
  const body = await response.text();
  for (const assertion of assertions) assertion(response, body);
}

const hasSecurity = (response) => {
  for (const name of ["content-security-policy", "strict-transport-security", "x-content-type-options", "x-frame-options", "referrer-policy"]) {
    if (!response.headers.has(name)) throw new Error(`missing ${name}`);
  }
};
await check("/robots.txt", 200, [hasSecurity, (_, body) => { if (!body.includes("Sitemap:")) throw new Error("missing sitemap link"); }]);
await check("/sitemap.xml", 200, [hasSecurity, (response) => { if (!/max-age=0|s-maxage=60/.test(response.headers.get("cache-control") ?? "")) throw new Error("unsafe sitemap cache"); }]);
await check("/api/public/v1/clubs/search", 400, [(response) => { if (response.headers.get("cache-control") !== "no-store") throw new Error("API must be no-store"); }]);
await check("/__teamzone_unknown_smoke__", 404, [hasSecurity, (_, body) => { if (/service_role|SUPABASE_|stack trace/i.test(body)) throw new Error("private error leaked"); }]);
console.log("PUB-06 synthetic smoke passed");
