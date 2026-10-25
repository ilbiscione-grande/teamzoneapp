# Auditrelease – 25 oktober 2026

Användaren godkände push, CI och driftsättning i den befintliga auditmiljön.
Implementation och dokumentation pushades till `main` i `d541a94`.
CI-rättningarna finns till och med `e0a6ffb`.

## CI

[GitHub Actions, revision e0a6ffb](https://github.com/ilbiscione-grande/teamzoneapp/actions/runs/40216643713).
**Samtliga sex jobb passerade:** Flutter analys/test, SQL/PGlite, public-site,
Webtools, Edge Functions och Firebase Functions. Körningen verifierar
kodrevisionen `e0a6ffb`; efterföljande dokumentationscommit ändrar inte kod.
Flutter: 810 tester. Webbplatserna: 94 respektive 54 tester. Edge: 29 tester.
SQL-jobbet körde alla 84 lokala testfiler och de tre extra PUB-07-lägena.

Den första körningen upptäckte två befintliga problem:

- Deno-testet för inloggningshandlern läser testkonfiguration och loggmetadata.
  CI ger nu endast dessa sex namngivna miljövariabler åtkomst; inga nätverks-
  eller filrättigheter har lagts till.
- Functions-låsfilens `body-parser` 2.3.0 hade
  [GHSA-27r3-jxmh-p828](https://github.com/advisories/GHSA-27r3-jxmh-p828).
  Låsfilen uppdaterades inom befintliga versionskrav till 2.4.0, med `qs`
  6.16.1. Ren installation, 8 tester och audit med noll fynd passerade lokalt
  och i GitHub. Patchen har driftsatts till de tre befintliga auditfunktionerna
  `criticalFlowAlertBridge`, `runCriticalFlowMonitor` och `clientErrorSink`.
  Firebase rapporterade Successful update operation för samtliga.
  Båda HTTP-funktionerna gav förväntat 405 för efterkontrollens GET-anrop.

## Driftsättning och efterkontroller

Firebase-projekt: `teamzoneapp-b02a2`. Inga migreringar, DNS-ändringar eller
produktionsprovisionering ingick. Webbplatsernas paket/låsfiler i den uppladdade
källan är samma som de verifierade i `d541a94`: Next.js 16.4.3.

| Yta | Mål | Resultat |
|---|---|---|
| Flutter | `hosting:test`, `https://app.teamzoneapp.se` | Firebase rapporterade release complete. |
| Public-site | `apphosting:teamzoneapp-public`, `https://teamzoneapp.se` | Firebase rapporterade rollout complete. |
| Webtools | `apphosting:teamzoneapp-webtools`, Firebase-origin | Firebase rapporterade rollout complete. |

Flutter byggdes med release-läge, `TEAMZONE_ENV=audit`, auditprojektets URL
och publika nyckel samt `PUBLIC_SITE_URL=https://public.teamzoneapp.se`.
Övriga feature-flaggor använder kodens befintliga standardvärden.
Miljögrinden `node ops/check_web_build.mjs audit` passerade.
Bygget gav en varning om ej medföljande CupertinoIcons-font; bygge och wasm-dry-run passerade.

Lokalt och publicerat `main.dart.js` har samma SHA-256:
`CAEA279A2C2FDD424B00F96C0940C2B286E9AAC4397D2A9A6B1C452B7B79638D`.

Efter färdiga utrullningar passerade public-site:s syntetiska PUB-06-smoke.
Appens rot, publiksajtens rot, `/klubbar`, `/api/public/v1/account-config`
och Webtools rot, `/logga-in`, `/tacticsboard`, `/api/config` gav HTTP 200,
`X-Content-Type-Options: nosniff` och `X-Frame-Options: DENY`.
Ingen inloggad visuell provning, fysisk enhetsacceptans eller native-release
ingick. Övriga releasegrindar i [aktuellt leveransläge](../implementation/current_status.md) kvarstår.
