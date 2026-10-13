// Predeploy guard for Firebase Hosting (firebase.json): refuses to deploy a
// Flutter web build to the wrong environment. The build must talk to the
// environment's own Supabase project (ops/environments.json) and to no other,
// and the target's CSP must name that project.
//
//   node ops/check_web_build.mjs audit|production
import { existsSync, readFileSync } from "node:fs";

const name = process.argv[2];
const targets = { audit: ["test", "build/web"], production: ["production", "build/web-production"] };
const fail = (message) => {
  console.error(`check_web_build (${name}): ${message}`);
  process.exit(1);
};
if (!targets[name]) fail("usage: node ops/check_web_build.mjs audit|production");

const { environments } = JSON.parse(readFileSync("ops/environments.json", "utf8"));
const ref = environments[name]?.supabaseProjectRef;
if (!ref) fail("the environment has no Supabase project yet (ops/environments.json)");
const others = Object.entries(environments)
  .filter(([other, env]) => other !== name && env.supabaseProjectRef)
  .map(([, env]) => env.supabaseProjectRef);

const [target, dir] = targets[name];
const hosting = JSON.parse(readFileSync("firebase.json", "utf8")).hosting.find((h) => h.target === target);
const csp = JSON.stringify(hosting?.headers ?? []);
if (!csp.includes(`https://${ref}.supabase.co`)) fail(`the CSP of hosting target "${target}" does not name ${ref}`);
for (const other of others) if (csp.includes(other)) fail(`the CSP of hosting target "${target}" names ${other}`);

const main = `${dir}/main.dart.js`;
if (!existsSync(main)) fail(`${main} is missing; build with --output ${dir}`);
const js = readFileSync(main, "utf8");
if (!js.includes(`https://${ref}.supabase.co`)) fail(`${main} is not built for ${ref} (SUPABASE_URL)`);
for (const other of others) if (js.includes(other)) fail(`${main} contains another environment's project (${other})`);
console.log(`check_web_build (${name}): ${dir} targets ${ref}`);
