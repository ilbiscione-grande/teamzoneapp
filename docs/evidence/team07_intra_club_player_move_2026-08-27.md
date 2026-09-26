# TEAM-07 – flytta spelare med bevarad historik

Datum: 2026-08-27  
Status: helt genomförd och fysiskt verifierad 2026-09-13

## Levererat

- Behörig ledare kan välja en eller flera aktiva spelare, ett annat aktivt lag i samma klubb och anledning i ett sammanhållet bottomsheet.
- Samma flöde kan öppnas från truppverktygen eller från en spelarprofil, där aktuell spelare är förvald.
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
- Migrationen är applicerad i det godkända testprojektet `hgcshgunvooyudvrcpig`.

## Verifiering

- Riktad `flutter analyze lib/src/features/roster/roster_surface.dart`: inga problem 2026-09-13.
- Ett widgettest, ett SQL-kontraktstest och ett modelltest har lagts till.
- Den fulla Flutter-sviten var grön 2026-09-07 och hosted rollback-testet för TEAM-07 passerar.
- Backendansluten debug-APK byggdes, installerades och startades på fysisk Android-tablet.
- En verklig spelare flyttades mellan två lag och tillbaka. Källagets aktiva lista och mållagets aktiva lista uppdaterades korrekt utan att historiken skrevs om.
- Fysisk uppföljning godkände flerval, profilgenväg, synlig resultatdialog och att hela flyttpanelen stängs efter en genomförd eller delvis genomförd flytt så nästa öppning hämtar färska kandidater.

## Slutbedömning

- TEAM-07 är stängd. Tabletgrinden täcker den responsiva klienten och samma capabilitystyrda serverkommando används i samtliga formfaktorer.
- Flytt mellan klubbar förblir medvetet ett separat flerpartsflöde och ingår inte i TEAM-07.
