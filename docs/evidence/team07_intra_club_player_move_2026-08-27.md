# TEAM-07 – flytta spelare med bevarad historik

Datum: 2026-08-27  
Status: lokalt genomförd, runtime-/fysisk/testgrind återstår

## Levererat

- Behörig ledare kan välja en aktiv spelare, ett annat aktivt lag i samma klubb, flyttdatum och anledning.
- Flytten avslutar den befintliga `team_assignments`-raden exakt vid ikraftträdandet och skapar en ny rad i samma transaktion.
- Den tidigare assignment-raden raderas eller skrivs inte om utöver slutstatus, slutdatum, revision och aktör.
- Event, närvaro och statistik muteras inte och kan därför fortsätta peka på sin historiska klubb-/lagkontext.
- Bakdatering utanför en kort transporttolerans avvisas. Flyttdatum får ligga högst två år framåt och måste vara efter assignmentens start.
- Samtidiga flyttar för samma person serialiseras med transaktionsbundet advisory lock. Förväntad revision och överlappskontroll stoppar stale eller kolliderande kommandon.
- Kommandot är idempotent och auditloggat med källa, mål, person och ikraftträdande.
- Cross-club använder fortsatt det separata befintliga source/target-/guardianflödet och blandas inte ihop med inom-klubbkommandot.

## Filer

- `lib/src/features/roster/roster_surface.dart`
- `lib/src/features/roster/roster_models.dart`
- `lib/src/features/roster/roster_services.dart`
- `lib/src/core/localization/app_strings.dart`
- `supabase/migrations/20260827053705_team07_intra_club_player_move.sql`
- `test/team07_intra_club_move_test.dart`

## Databas- och säkerhetsgräns

- Både käll- och mållag kräver `club.memberships.manage`; klubbscopad capability täcker båda.
- Läsmodellen returnerar endast aktiva personer i källaget och andra aktiva lag i samma klubb.
- Security-definer-funktionerna ligger i `internal`, använder tom `search_path`, autentiseringskontroll och explicita revoke/grant.
- Ett partiellt sammansatt index stöder den återkommande aktiva person-/lagfrågan.
- Postgres-praktikskillen styrde valet av transaktionsbundet advisory lock och partiellt index.
- Liveprojektet `hgcshgunvooyudvrcpig` har inte ändrats.

## Verifiering

- `flutter analyze`: inga problem.
- Ett widgettest, ett SQL-kontraktstest och ett modelltest har lagts till.
- Flutter-testwrappen startade upprepade gånger utan output eller kvarvarande synlig testprocess och avbröts efter begränsad väntan; testresultat får därför inte anges som godkänt ännu.

## Kvarstående grindar

- Migrationen är lokal och har inte körts mot Supabase live.
- Docker/lokal PostgreSQL saknas, så SQL-fixtures, `EXPLAIN` och advisors återstår.
- TEAM-07-testet och rosterregressionen ska köras när Flutter-testwrappen svarar.
- Fysisk verifiering på phone/tablet/desktop återstår.
