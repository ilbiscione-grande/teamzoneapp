# Webtools i CI – 25 oktober 2026

## Ändring

`.github/workflows/ci.yml` har ett separat `webtools`-jobb, utformat som den
publika sajtens befintliga jobb:

- Ubuntu-runner, Node 24 och 15 minuters timeout.
- npm-cache med `webtools/package-lock.json` som nyckelunderlag.
- `npm ci`, `npm run lint`, `npm test`, `npm run build` och
  `npm audit --omit=dev --audit-level=high`, i den ordningen.
- Befintliga triggers: pull requests, push till `main` och manuell dispatch.
- Endast `contents: read`; inga tjänstehemligheter eller deploymentsteg.

Ändringen har nu pushats och sajtjobben har passerat på GitHubs Ubuntu-runner.
Båda sajterna har driftsatts till audit; se [releasekvittot](audit_release_2026-10-25.md).

## Säkerhetsfynd vid ren verifiering

En tillfällig kopia av Webtools skapades av de 164 spårade filerna, utan
befintliga `node_modules`, `.next`, miljöfiler eller typkontrollcache.
Supabase- och tjänstekonfiguration rensades ur verifieringsprocessens miljö.
På den ursprungliga Next.js-versionen 16.3.8 passerade installation,
typkontroll, 54 tester och produktionsbygge, men säkerhetsgrinden stoppade
körningen med ett kritiskt paketfynd.

Npm rapporterade följande advisories för `next`:

- [SVG/image-optimization](https://github.com/advisories/GHSA-2464-fhr4-w9xw).
- [Server Actions, denial of service](https://github.com/advisories/GHSA-p3m5-59mp-jv5r).
- [Cache-funktioner och typed arrays](https://github.com/vercel/next.js/security/advisories/GHSA-673q-mjm6-r5xr).

Den tidigare rapportens nollfynd avser den dåvarande npm-kontrollen och ska
inte användas som dagens garanti. Fyndet gäller den installerade versionen;
ingen exploatering eller kompromettering har konstaterats i denna genomgång.

Npm rekommenderade 16.4.3. Båda sajterna använde samma 16.3.8-version, så
rättningen omfattar både `public-site` och `webtools`, med exakt låst Next.js
16.4.3 och uppdaterade låsfiler. Grinden har inte sänkts och `audit fix --force`
har inte använts. Se [utgivarens release](https://github.com/vercel/next.js/releases/tag/v16.4.3).

## Slutlig verifiering

Samtliga fem kommandon kördes sekventiellt med kontroll av exitkod i två
rena kopior av den uppdaterade koden, utan miljöfiler och gammal bygg-/typcache:

| Kontroll | Webtools | Public-site |
|---|---|---|
| `npm ci` | Godkänd | Godkänd |
| `npm run lint` | Godkänd | Godkänd |
| `npm test` | 54/54 godkända | 94/94 godkända |
| `npm run build` | Godkänt, Next.js 16.4.3 | Godkänt, Next.js 16.4.3 |
| `npm audit --omit=dev --audit-level=high` | 0 sårbarheter, exit 0 | 0 sårbarheter, exit 0 |

Även installationernas fulla npm-audits rapporterade noll fynd. Låsfilsdiffarna
avser Next.js och dess `@next/env`/plattformsspecifika SWC-paket; andra
paketversioner ändrades inte. `git diff --check` passerar. Befintligt
kontraktstest för public-site:s Server Action-gräns passerar mot den nya
installerade Next-versionen.

Efter användarens godkännande genomfördes push, GitHub-körning och
driftsättning. Båda sajtjobben passerade även på Ubuntu. Releasekvittot
redovisar miljö, revision, utrullning och efterkontroller.
