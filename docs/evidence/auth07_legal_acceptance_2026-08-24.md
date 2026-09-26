# AUTH-07 – Villkor, integritet och frivilliga samtycken

**Datum:** 2026-08-24  
**Status:** TEKNISKT HOSTED-VERIFIERAD; PUBLIKA PLACEHOLDERS DRIFTSATTA, JURIDISKT GODKÄNNANDE OCH SLUTLIG FYSISK GRIND ÅTERSTÅR
**Livepåverkan:** Migrationen är applicerad mot det godkända Supabase-testprojektet `hgcshgunvooyudvrcpig`.

> **Releaseblocker:** Placeholdertexterna är endast tillåtna under intern testning. Appen får inte lanseras till extern publik förrän juridiskt ansvarig har ersatt och godkänt samtliga placeholders, de slutliga dokumenten har publicerats som en ny materiell version och acceptansflödet har verifierats mot den versionen.

## Implementerat

- En autentiserad användare passerar en fail-closed juridisk statusgrind innan profil, klubb eller lagdata laddas.
- Aktiv version och publik URL lagras separat för användarvillkor respektive integritetspolicy.
- Användaren intygar separat att villkoren godkänns och att integritetspolicyn har lästs.
- Acceptansen lagras per profil, dokumenttyp och exakt version med tidpunkt och källa.
- En ny aktiv materiell version saknar automatiskt acceptans och visar därför grinden igen.
- Servern avvisar stale submit om dokumentversionen ändrats medan formuläret varit öppet.
- Marknadsföring är en separat frivillig inställning, är av som standard och krävs aldrig för att fortsätta.
- Marknadsföring kan senare stängas av eller aktiveras i Integritetsinställningar utan påverkan på appfunktionerna.
- Acceptans och ändrad marknadsföringsinställning är idempotenta och har separata auditkommandon.
- Generella juridiska attesteringar använder inte och ändrar inte tabellerna för minderårig-, guardian- eller publiceringssamtycke.
- All ny användartext har svensk och engelsk lokalisering.

## Verifiering

- Direkt Flutter-analys: **No issues found**.
- Riktad AUTH-04–AUTH-07/FND-05-svit: **18/18 passerar**.
- Widgettest verifierar att appinnehåll blockeras, båda obligatoriska attesteringarna krävs och marknadsföring förblir av om användaren inte väljer den.
- Källkontrakt verifierar versionslås, false-default, separat opt-out-kommando, audit och frånvaro av guardian-/publiceringskoppling.
- Lokalisering och tillgänglighetsregression passerar.
- Säkerhetsutformningen följer aktuell Supabase-vägledning: privata tabeller, explicit RLS/revoke, tom `search_path` och explicita funktionsgrants.
- Migrationen ingår i den synkade hosted migrationsbackloggen som stängdes 2026-09-04.
- Hosted rollback-matris verifierar fail-closed status utan acceptans, separata villkors-/integritetsversioner, marknadsföring av som standard, acceptans, separat opt-in, idempotent retry, audit, anon-nekande och att en ny materiell villkorsversion återöppnar endast villkorsgrinden.
- Matrisen hittade att en redan lyckad acceptans kunde ge `legal_version_changed` vid retry efter ett senare versionsbyte. Framåtmigration `20260911044257_auth07_fix_legal_acceptance_replay.sql` läser aktörsbunden dedupe före kontrollen av nu aktiv version; ett nytt stale-kommando nekas fortfarande.
- Riktat AUTH-07-test: **3/3 passerar**. Full Flutter-regression: **363/363 passerar** och full analys är ren.
- Lokal och remote migrationshistorik är helt synkad genom `20260911044257`.
- Fysisk Android-kontroll på Xiaomi Mi 9 bekräftar att grinden visas före appinnehåll, visar separata versioner och obligatoriska kryssrutor, har frivillig marknadsföring av som standard och håller **Godkänn och fortsätt** inaktiv tills både villkor och integritet har markerats.
- Dokumentlänkskontrollen stoppade godkännandet: `/villkor` ledde användaren till inloggningssidan. En direkt HTTP-kontroll 2026-09-11 visade dessutom att både `https://teamzoneapp.se/villkor` och `https://teamzoneapp.se/integritet` returnerar samma generiska Netlify-appskal (`title: teamzoneapp`) utan villkors- eller integritetstext. Att integritetslänken kan öppnas räcker därför inte som juridisk dokumentverifiering.
- De två tidigare acceptansraderna för testkontot återställdes exakt med ursprunglig version, tidpunkt och källa efter den avbrutna kontrollen. Marknadsföringsval, medlemskap och support-adminroll ändrades inte.
- Den separata marknadsföringsinställningen verifierades därefter fysiskt: av → på → beständig på efter full appomstart → av och sparad. Skrivskyddad hosted-kontroll bekräftade slutvärde `false`, revision 3, exakt två nya `identity.marketing.preference.v1`-audithändelser och fortsatt två aktiva juridiska acceptanser. Ingen appfunktion eller supportbehörighet påverkades.
- Två separata, responsiva platshållarsidor finns nu på `https://public.teamzoneapp.se/villkor` och `https://public.teamzoneapp.se/integritet`. De innehåller läsbara grundavsnitt men är tydligt märkta **Juridiskt utkast för teknisk testning**, innehåller synliga placeholders och skickar `noindex`; de får inte betraktas som juridiskt godkända slutdokument.
- Publiksajtens 29/29 tester, TypeScript-kontroll och Next-produktionsbygge passerar. Efter rollout på den befintliga App Hosting-backenden `teamzoneapp-public` svarar båda URL:erna med `200`, rätt separata sidtitlar, utkastmarkering och `noindex`, utan inloggningsskal.
- Migration `20260911184009_auth07_public_legal_document_urls.sql` är applicerad och registrerad remote. Den ändrar endast de aktiva dokumentens `public_url` till de fungerande publika adresserna. Version `2026-08-24`, materiell status och samtliga befintliga acceptanser lämnas oförändrade, eftersom placeholdertexten inte ska framställas som ett nytt juridiskt avtal.
- Inställningar visar nu de två aktuella dokumenten separat med versionsrad och extern öppningsikon. En backendansluten debug-APK byggdes och installerades över befintlig app utan datarensning. Fysisk Xiaomi Mi 9-verifiering 2026-09-12 bekräftade att **Användarvillkor** öppnar rätt villkorssida och att **Integritetspolicy** öppnar rätt integritetssida; båda visar sin korrekta rubrik och den gula utkastmarkeringen.

## Kvarvarande grind

1. Privacy/legal måste ersätta placeholderuppgifter, granska dokumenttexterna och godkänna slutliga versionsbeteckningar. De nu publicerade utkasten är endast till för teknisk flödesverifiering.
2. Publicera därefter de godkända texterna som en ny materiell dokumentversion så att en ny uttrycklig acceptans krävs.
3. Slutför fysisk Android-granskning av acceptans, textskalning och fokus, och kör motsvarande webbgrind. Dokumentlänkarna samt marknadsföringens opt-in, beständighet och opt-out är redan fysiskt godkända.

Alla tre punkter ovan är obligatoriska innan extern publik lansering. De får inte skjutas upp till efter go-live eller stängas enbart med de nuvarande placeholderdokumenten.

Ingen ändring gjordes i äldre TeamZone-projekt eller äldre databaser.
