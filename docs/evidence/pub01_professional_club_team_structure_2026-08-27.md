# PUB-01 – professionell klubb- och lagstruktur

Datum: 2026-08-27  
Omfattning: lokal Next.js-publiksajt; ingen driftsättning och ingen Supabase-liveändring.

## Genomfört

- Klubbens standardsida `/{clubslug}` har officiell profilhero, klubbmärke när en publicerad variant finns, verifieringsmarkör och ankarnavigation för om klubben, nyheter, lag, händelser, partners och kontakt.
- Publicerade klubbnyheter hämtas via den befintliga service-only projection-gränsen. Saknade lag, händelser, partners eller redaktionellt innehåll visas som ärliga, professionella tomlägen.
- Varje `/{clubslug}/{teamslug}` är en officiell lagkanal under klubben med klubbåterväg, översikt, lagnyheter samt tidigare och kommande publika händelser.
- Metadata använder publicerat namn, beskrivning, canonical och Open Graph. Avstängd/otillgänglig publicering är noindex; okända slugs använder riktig 404-yta.
- Serverhämtningar memoiseras per render så metadata och sida delar klubb-/laguppslag utan onödiga dubbla läsningar.

## Verifiering

- `npm run lint`: godkänd.
- `npm test`: 9/9 godkända, inklusive tre PUB-01-strukturtester och befintliga säkerhets-/CAPTCHA-tester.
- `npm run build`: godkänd Next.js 16.3.1-produktionsbuild; klubb- och lagroutes är dynamiskt serverrenderade och 404-sidan prerenderas.

## Kvarstående grindar

- Fysisk visuell granskning med en uttryckligen publicerad lokal/hosted fixture på mobil och desktop.
- PUB-02 ska färdigställa katalog och publiceringsmodell; PUB-04 ska fylla full klubbövergripande event- och partnerprojektion. PUB-01 visar inte privat data och skapar inga falska exempelposter.
