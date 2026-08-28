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

## Verifiering

- `npm run lint`: godkänd.
- `npm test`: 15/15 godkända.
- `npm run build`: godkänd.
- Statisk kontraktskontroll täcker allowlistade eventfält, atomisk avpublicering, HTTPS, ren/färdig mediavariant, CAPTCHA, same-origin, rate limit, neutral respons och retention.

## Återstår före full klarmarkering

- Autentiserad Flutter-UX för event-/partnerpublicering och tydlig förhandsgranskning.
- Mediaworker och faktisk publik leveransväg för skannade, transformerade bilder.
- PostgreSQL-runtime och Security/Performance Advisors när godkänd databas finns.
- Fysisk visuell kontroll med publicerade fixtures på mobil och desktop.
- Separat uttryckligt godkännande före eventuell Supabase-liveändring.

Ingen livepush, driftsättning, webtools eller workspace utfördes.
