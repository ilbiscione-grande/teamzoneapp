# TEAM-05 – guardian och riktad inbjudan

Datum: 2026-08-27  
Status: genomförd samt hosted och fysiskt webbverifierad; Android/iOS-deep-linkgrind spåras under AUTH-03

## Levererat

- Administrationsytan kan skapa mottagarbunden rosterinvite, guardianinvite och generell lagkod.
- Rå kod visas endast direkt efter skapande; databasen lagrar enbart SHA-256-hash.
- Status, utgångsdatum och återkallelse visas för riktade invites, guardianinvites och lagkoder.
- Generell lagkod ger aldrig direkt medlemskap. Den skapar en väntande `membership_application` med kodens förvalda roll och går genom befintlig klubbgranskning.
- Kod har maxdatum, användningstak, revisionslås, idempotens och neutral ogiltig/utgången status.
- Guardianinvite kräver befintlig avsedd guardianprofil, safeguardingmarkerat barn, högst sju dagars giltighet och acceptans från exakt länkat guardiankonto.
- Aktiv guardianrelation listas dataminimerat och kan avslutas av det verifierade guardiankontot eller `club.safeguarding.manage`.
- Guardianens egna avslut auditmärks med explicit `acting_as_guardian_person_id`; barnets övriga uppgifter exponeras inte.

## Filer

- `lib/src/features/roster/roster_surface.dart`
- `lib/src/features/roster/roster_models.dart`
- `lib/src/features/roster/roster_services.dart`
- `lib/src/core/localization/app_strings.dart`
- `supabase/migrations/20260826203502_team05_invite_guardian_lifecycle.sql`
- `test/team05_invite_guardian_test.dart`

## Säkerhetsgräns

- Riktad invite fortsätter använda AUTH-03:s mottagarhash, atomiska claim och neutral review-status.
- Teamkoder kan endast utfärdas och administreras med `club.memberships.manage`.
- Guardianinvite och relationsavslut följer befintlig safeguarding-capability och kontobindning.
- Alla nya definer-funktioner ligger i `internal`, har tom `search_path`, autentiserings-/tenantkontroll och explicit revoke/grant.
- Nya kommandon är idempotenta, revisionskontrollerade och auditloggade.
- TEAM-05:s sammansatta API finns i den uttryckligen godkända testdatabasen `hgcshgunvooyudvrcpig`.

## Verifiering

- `flutter analyze`: inga problem.
- `flutter test test/team05_invite_guardian_test.dart`: 4/4 passerar.
- Samlad TEAM-03–05, AUTH-03 och S02-regression: 21/21 passerar före den slutliga klientkopplingen för relationsavslut; den efterföljande TEAM-05-sviten är fortsatt 4/4 grön.
- Aktuell Supabase-dokumentation för funktionsprivilegier, definer/search_path och 2026 års Data API-förändringar kontrollerades.

### Hosted runtime 2026-09-01

- Åtta centrala API-signaturer för riktad invite, guardianinvite/-acceptans, lagkod, adminlista, revoke och relationsavslut finns i testdatabasen.
- Samtliga kan exekveras av `authenticated`; `anon` och `PUBLIC` saknar execute.
- Kontrollen var skrivskyddad och skapade eller ändrade inga invites, koder eller guardianrelationer.
- Omsprungen TEAM-05-regression passerade 4/4 och riktad analys gav inga problem.

### Hosted sorteringsregression 2026-09-01

- Fysisk webbtest hittade HTTP 400 när `list_invitation_admin` anropades.
- PostgreSQL-loggen bekräftade `invalid UNION/INTERSECT/EXCEPT ORDER BY clause`; adminprojektionen sorterade direkt över `UNION ALL`.
- `20260901150836_team05_fix_invitation_admin_ordering.sql` kapslar projektionen i en namngiven delmängd och sorterar därefter på dess explicita resultatkolumner.
- Korrigeringen passerade 5/5 tester, riktad analys och rollback-kompilering. Efter driftsättning gav en transaktionsbunden körning med befintligt behörigt lagkontext `runtime_ok=true` utan datamutation.
- Migreringshistoriken matchar den lokala versionen `20260901150836`.
- Nästa fysisk test visade ingen ny listpost. Skrivskyddad kontroll gav noll nyligen skapade invites och API-loggen saknade create-anrop: klienten hade stängt dialogen tyst när e-postfältet inte passerade lokal kontroll.
- Dialogen behåller nu ogiltig adress med tydligt fältfel, använder skrollbart innehåll och saknar den controller-dispose-race som hittades av regressionstestet. Giltig adress verifieras genom riktigt serviceanrop i widgettestet.
- TEAM-05 passerar därefter 6/6 och riktad analys är ren. Den Supabase-konfigurerade webbbuilden på port 5000 innehåller den nya valideringen och svarar med HTTP 200.

### Lagomfattad invite-behörighet 2026-09-01

- Fysisk webbtest med giltig e-post gav HTTP 403 från `issue_roster_invitation_v2`; PostgreSQL-loggen bekräftade `not_found` vid samma tidpunkt.
- Grundfunktionen kontrollerade endast `club.memberships.manage` med `team_id = null`, vilket felaktigt uteslöt en ledare med lagomfattad behörighet.
- `20260901202344_team05_allow_team_scoped_targeted_invite.sql` tillåter nu riktad invite när mottagaren har en aktiv placering i ett lag där aktören har `team.roster.manage` eller `club.memberships.manage`. Klubbomfattad behörighet fungerar fortsatt, men ingen bredare klubbåtkomst ges.
- Funktionen är applicerad i testdatabasen och migrationshistoriken är synkroniserad till lokal version. En transaktionsbunden runtimekontroll hittade tre behöriga aktör/mottagarpar och skapade en invite utan fel; hela transaktionen rullades tillbaka.
- Säkerhetsrådgivaren rapporterade inga nya varningar kopplade till ändringen. Befintliga informationsnotiser för privata/RPC-skyddade tabeller och den sedan tidigare avstängda leaked-password-kontrollen är oförändrade.
- Fysisk omtest godkänd: riktad kod skapades, inbjudan visades i adminlistan och kunde återkallas. Det råa statusvärdet `revoked` som då visades har lokaliserats till `Återkallad` inför nästa webbbuild.

### Återvisningsbar lagkod 2026-09-01

- Lagkoder skiljs nu från personliga inbjudningskoder: nya lagkoder behåller SHA-256-hashen för anspråk men sparar den återvisningsbara koden krypterat i Supabase Vault.
- `api.reveal_team_join_code` kräver `club.memberships.manage` för kodens exakta lag, tillåter bara en aktiv och användbar kod och auditloggar varje visning som `roster.team_code.reveal.v1`.
- `authenticated` har ingen direkt läsrätt till `vault.decrypted_secrets`; klartext lämnas endast från den behörighetskontrollerade RPC:n.
- Klienten visar en kompakt Visa kod-åtgärd för aktiva lagkoder och dialogen erbjuder kopiering. Riktade och guardianbundna koder fortsätter att visas endast vid skapandet.
- Hosted create→Vault-reveal→audit verifierades med identisk kod i en helt återställd transaktion. Migrationshistoriken matchar lokal version `20260901211827`, och säkerhetsrådgivaren gav inga nya fynd från ändringen.
- Lagkoder skapade före migrationen har ingen Vault-kopia och kan inte återställas; de ska återkallas och ersättas.
- Riktad klientanalys är ren. Den konfigurerade releasebuilden innehåller `reveal_team_join_code` och den svenska kopieringsbekräftelsen och serveras med HTTP 200 på port 5000. Widgettestprocessen kunde inte slutföras i den lokala Flutter-miljön och ersätts tills vidare av buildkontroll plus fysisk webbtest.

### Guardianförutsättning och lagscope 2026-09-01

- Fysisk test gav två HTTP 403/`not_found`. Skrivskyddad kontroll visade att samtliga tre personer i testlaget saknade `safeguarding_required`, samtidigt som klienten ändå tillät valfri person som barn.
- Personredigeringen har nu reglaget `Behöver vårdnadshavarkoppling`. Ändringen sker genom ett separat revisions- och idempotensskyddat kommando och auditloggas utan att ändra global identitet.
- Guardian-dialogen listar endast markerade barn och visar ett konkret tomlägesmeddelande om inget barn är behörigt.
- Invitekontrollen accepterar nu klubbomfattad safeguardingbehörighet eller `club.safeguarding.manage`/`club.memberships.manage` för barnets exakta aktiva lag. Den ger ingen åtkomst till andra lag.
- Hosted markera-barn→skapa-invite→audit passerade i en helt återställd transaktion. Riktad klientanalys är ren, migrationshistoriken matchar `20260901215526` och säkerhetsrådgivaren gav inga nya fynd från ändringen.

## Kvarstående grindar

- TEAM-05:s webbflöde är godkänt. Android/iOS-deep-linkverifiering spåras fortsatt av AUTH-03.

## Fysisk verifiering 2026-09-02–03

- Riktad inbjudan kunde skapas, visades i adminlistan och kunde återkallas.
- Aktiv lagkod kunde visas igen och kopieras; ett annat konto kunde använda koden och få rätt lagkoppling.
- Guardianinbjudan kunde skapas och användas av exakt avsett guardiankonto.
- Ny guardianrelation blev tillgänglig efter kontextomladdning och guardian kunde välja sin särskilda lagkontext.
- Guardian såg lag, kalender, event och tillåtna mottagare enligt rollen.
- CAL-10 verifierade dessutom att guardian endast såg valt barn i privat läge och hela kallade-listan i delat läge, utan andra deltagares närvaro eller ledaråtgärder.
- Kontextväljaren visar efter korrigering både lag och roll, exempelvis `Thomas lag · Vårdnadshavare`, vilket skiljer guardian- och spelarkontexter åt.
- En riktig riktad invite öppnades före inloggning på webb, återupptogs efter inloggning med exakt mottagarkonto och landade efter lyckad acceptans på Hem. Testinviten återkallades därefter.
