# TEAM-05 – guardian och riktad inbjudan

Datum: 2026-08-27  
Status: lokalt genomförd, runtime-/fysisk grind återstår

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
- Liveprojektet `hgcshgunvooyudvrcpig` har inte ändrats.

## Verifiering

- `flutter analyze`: inga problem.
- `flutter test test/team05_invite_guardian_test.dart`: 4/4 passerar.
- Samlad TEAM-03–05, AUTH-03 och S02-regression: 21/21 passerar före den slutliga klientkopplingen för relationsavslut; den efterföljande TEAM-05-sviten är fortsatt 4/4 grön.
- Aktuell Supabase-dokumentation för funktionsprivilegier, definer/search_path och 2026 års Data API-förändringar kontrollerades.

## Kvarstående grindar

- Migrationen är lokal och har inte körts mot Supabase live.
- Docker/lokal PostgreSQL saknas, så SQL-fixtures och advisors återstår.
- AUTH-03:s lokala/hosted Edge- och deep-link-grind återstår.
- Fysisk verifiering av kodskapande, status/revoke, lagkod och guardianavslut återstår.
