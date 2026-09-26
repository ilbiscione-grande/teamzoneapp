# Resultat direkt på matchens detaljsida

Status: aktiverat i testprojektet efter användarens godkännande. Migrationen är applicerad och critical-flow-command version 9 är aktiv med fortsatt JWT-verifiering.

Kalender → match → Info visar resultatkort med Registrera resultat. Behörig ledare anger lagets och motståndarens mål och sparar/avslutar i samma operation. Avslutade resultat kan rättas med anledning. Framtida, inställda och arkiverade matcher kan inte avslutas här. Delad läsbehörighet visar inget redigeringskommando.

RPC `api.register_match_result` använder behörighetskontroll, revisionskontroll för både match och kalenderhändelse, matchlås, eventradlås och idempotent kommandokvitto. Matchfakta bevaras. Separat spårade poängjusteringar korrigerar totalsumman utan påhittade målskyttar. Kalenderhändelsen avslutas via befintligt revisions-/auditflöde. Befintliga PUB08-triggers styr offentlig visning utifrån laginställningen; inga laginställningar ändras av migrationen.

Dialogen återanvänder kommandonyckeln vid osäkert återförsök. Misslyckad inläsning medger ingen skrivning. Ett bekräftat sparande förblir lyckat även om efterföljande siduppdatering misslyckas. Resultatkortet uppdateras också när Match Space stängs.

Verifiering:

- `flutter analyze --no-pub`: inga anmärkningar.
- `flutter test --no-pub test/cal11_event_details_page_test.dart`: 13 tester godkända, inklusive fyra för resultatflödet.
- `node supabase/tests/pub07_personal_home.local.mjs --direct-result`: isolerad PostgreSQL med verkliga matchfunktioner och publiceringstriggers. Avslut, färskt 0–0, rättelse med anledning, idempotens, revisionskonflikt, felaktiga värden, obehörig/utloggad, fel eventtyp, inställt/arkiverat/framtida, bevarade matchfakta, negativa råsummor samt lagstyrd offentlig publicering verifierade.
- Hosted transaktionstest som authenticated: avslut via kalenderövergång, rättelse, 0–0, idempotent återförsök, revisionskonflikt, obligatorisk rättelseanledning och bevarad historik godkända. Anonym exekvering är spärrad. Alla teständringar rullades tillbaka; efterkontroll bekräftade ursprungligt resultat 3–1 och ursprungliga revisioner.
- Gateway: endast den nya operationen läggs till. Befintlig JWT-verifiering är på och ska bevaras vid driftsättning.

Aktiverat: migration `20260926070459_match_direct_result_registration.sql` och operationen i `critical-flow-command` på testprojekt `hgcshgunvooyudvrcpig`. Säkerhetskontrollen visar samma befintliga kategorier som tidigare: RLS utan policy och läckta lösenordsskydd avstängt. Flutter-servern på port 5000 har kompilerats om; ingen webbläsarklient var ansluten vid omladdningen. Ingen public-site-driftsättning krävs.
