# TEAM-08 – arkivering, borttagning och anonymisering

Datum: 2026-08-27  
Status: lokalt genomförd, runtime-/Auth-worker-/fysisk/testgrind återstår

## Levererat

- Ledare kan avsluta en aktiv lagrepresentation med anledning. Personen visas därefter under det separata filtret `Tidigare`.
- Assignment-raden raderas inte; den får explicit slutstatus, sluttid, aktör och revision.
- En lagansvarig kan initiera klubbens PII-radering. En separat klubbfunktionär med klubbscopad capability måste godkänna och initiatorn får inte godkänna sin egen begäran.
- Godkänd klubbanonymisering ersätter namn med `Tidigare spelare`, rensar lokala personfält och avslutar assignments, account links, guardianrelationer, eligibilities och öppna invites.
- Event, närvaro, statistik, matchfakta och andra historiska verksamhetsrader raderas eller skrivs inte om.
- En användare kan skapa en global raderingsbegäran, men endast service role/TeamZone kan granska den. Granskaren måste vara en annan profil än initiatorn.
- Global granskning anonymiserar alla klubbrepresentationer och den kvarvarande profiltombstonen. Slutmarkering nekas medan Auth-användaren fortfarande finns.
- `core.profiles` frikopplas från `auth.users ON DELETE CASCADE`, så Auth Admin kan ta bort kontot medan neutral audit- och historikreferens ligger kvar.
- Alla aktiva länkar avslutas före Auth-radering; kvarvarande eller gammal session saknar därmed relationsbaserad behörighet.

## Filer

- `lib/src/features/roster/roster_surface.dart`
- `lib/src/features/roster/roster_models.dart`
- `lib/src/features/roster/roster_services.dart`
- `lib/src/core/localization/app_strings.dart`
- `supabase/migrations/20260827055529_team08_roster_lifecycle_erasure.sql`
- `test/team08_roster_lifecycle_test.dart`

## Databas- och säkerhetsgräns

- Vanlig arkivering och initiering kräver `club.memberships.manage` i lagkontext.
- Godkännande kräver klubbscopad `club.memberships.manage` och en annan autentiserad profil.
- Global review/finalize är återkallad för anon/authenticated och uttryckligen endast granted till `service_role`.
- Finalize kräver att den berörda raden saknas i `auth.users`; Auth Admin-radering ska göras av separat serverworker och aldrig av klienten.
- Security-definer-funktionerna ligger i `internal` eller har service-only API-grind, tom `search_path`, explicit auth/current-user-kontroll och revoke/grant.
- Partiella index används för öppna raderingsärenden och transaktionsbundna advisory locks serialiserar personlivscykeln.
- Liveprojektet `hgcshgunvooyudvrcpig` har inte ändrats.

## Verifiering

- `flutter analyze`: inga problem.
- Ett widgettest, ett SQL-kontraktstest och ett modelltest har lagts till.
- Flutter-testwrappen startade utan output även med `--no-pub` och avbröts efter begränsad väntan; testresultat anges därför inte som godkänt.
- Statisk kontroll bekräftar dual control, service-only global review, neutralisering, Auth-existensgrind och frånvaro av hard-delete för roster/eventhistorik.
- Supabase/Postgres-praktikskillen styrde partiella index och transaktionsbundna advisory locks.

## Kvarstående grindar

- Migrationen är lokal och har inte körts mot Supabase live.
- Docker/lokal PostgreSQL saknas, så fixtures, constraints, `EXPLAIN` och advisors återstår.
- Auth Admin-worker för faktisk kontoradering och därefter finalize ska integreras och verifieras separat.
- TEAM-08-testet och rosterregressionen ska köras när Flutter-testwrappen svarar.
- Fysisk verifiering på phone/tablet/desktop återstår.
