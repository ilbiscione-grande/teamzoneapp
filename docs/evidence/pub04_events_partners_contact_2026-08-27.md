# PUB-04 – publika event, partners och kontakt

Datum: 2026-08-27  
Status: lokalt genomfört, runtime- och UX-verifiering återstår

## Levererad gräns

- `publication.manage` krävs för revisionerad publicering och avpublicering av event och partners.
- Eventprojektionen innehåller endast publik titel, starttid, eventtyp och valfri explicit publicerad plats. Intern beskrivning, deltagare, kallelser och närvaro lämnar aldrig eventaggregatet.
- Klubbsidan sammanställer publicerade händelser från publicerade lag inom ett begränsat tidsfönster; lagsidan behåller sin tidigare/kommande-lista.
- Partners kan vara utkast, publicerade eller avpublicerade. Externa länkar måste använda HTTPS och renderas med `noopener noreferrer`.
- Partnerlogotyp kan endast publiceras efter servicekontrollerad registrering, ren skanning och färdig publik variant. Privata meddelandefiler återanvänds inte.
- Kontaktflödet kräver same-origin och verifierad CAPTCHA, begränsas till fem försök per klubb och timme, validerar alla maxlängder och raderar innehåll efter högst 30 dagar.
- Okänd, opublicerad eller utgången klubb får samma neutrala accepterade svar. En äldre kontroll mot det borttagna läget `draft` korrigerades till `published` plus aktiv publiceringsbekräftelse.
- Alla nya tabeller har RLS som defense-in-depth, inga direkta klientgrants och `SECURITY DEFINER`-funktioner har explicit revoke/grant.
- Flutter-redaktionen länkar till en publiceringspanel där behöriga användare kan förhandsgranska och ändra eventpublicering samt hantera partnerposter.
- Den lokala, ej utrullade migrationen `20260828090546_pub04_publication_management_list.sql` returnerar endast publicerbara event inom ett begränsat tidsfönster och filtrerar varje event genom lagets `publication.manage`. Partnerlistan kräver klubbmandat.
- Klienten erbjuder ingen osäker genväg för logotyper; mediauppladdning visas som ej konfigurerad tills worker, skanning och publik variant finns.
- Den lokala migrationen `20260828092016_pub04_public_media_delivery.sql` definierar privata source-/variantbuckets, capabilitystyrd staging, låst servicekö, WebP-only slutkontroll och service-only tokenupplösning.
- `public-media-worker` kräver en HTTPS-provider och hemlig nyckel innan den ens claimar arbete. Den begär skanning, metadata-strip och begränsad WebP-transformering; saknad provider ger 503 och ingen publicering.
- Publiksajten levererar endast clean/ready-varianter via `/media/public/{opaque-token}` med `nosniff` och lång immutable CDN-cache. Originalfiler exponeras aldrig.

## Verifiering

- `npm run lint`: godkänd.
- `npm test`: 15/15 godkända.
- `npm run build`: godkänd.
- Statisk kontraktskontroll täcker allowlistade eventfält, atomisk avpublicering, HTTPS, ren/färdig mediavariant, CAPTCHA, same-origin, rate limit, neutral respons och retention.
- `dart analyze lib test`: godkänd utan anmärkningar den 2026-08-28.
- PUB-03/PUB-04-, lokalisering- och scope-tester: godkända.
- Full Flutter-regression: 274/274 tester godkända den 2026-08-28.
- Publiksajtens TypeScript-kontroll, 25/25 Node-tester och Next-produktionsbuild inklusive media-routen är godkända den 2026-08-28.

## Återstår före full klarmarkering

- Val och konfiguration av faktisk skannings-/transformeringsprovider samt upload-UX när providern är godkänd.
- PostgreSQL-runtime och Security/Performance Advisors när godkänd databas finns.
- Fysisk visuell kontroll med publicerade fixtures på mobil och desktop.
- Separat uttryckligt godkännande före eventuell Supabase-liveändring.

Ingen livepush, driftsättning, webtools eller workspace utfördes.
