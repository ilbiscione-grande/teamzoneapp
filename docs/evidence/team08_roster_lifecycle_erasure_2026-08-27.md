# TEAM-08 – arkivering, borttagning och anonymisering

## Begreppsbeslut 2026-09-13

- `Avsluta i laget` är normalåtgärden när en spelare slutar, pausar eller byter sammanhang. Namn, matcher, närvaro och personliga rekord bevaras i den historiska lagkontexten.
- `Begär anonymisering` är en separat integritetsåtgärd. Namn och identifierande uppgifter ersätts av `Tidigare spelare`; lagets neutrala verksamhetsfakta och referenser bevaras, men personliga rekord kan inte längre tillskrivas individen.
- `Radera hela kontot` är ett separat globalt, TeamZone-granskat Auth-flöde.
- Intern historik och publik visning är skilda beslut. Regler för publik namngiven historik, särskilt för minderåriga, ska fastställas före extern lansering.

Datum: 2026-08-27  
Status: genomförd och slutverifierad i hosted testmiljö samt på fysisk Android-tablet

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
- `supabase/migrations/20260913124518_team08_global_person_erasure_worker.sql`
- `supabase/migrations/20260913131353_team08_restore_archived_assignment.sql`
- `supabase/migrations/20260913133759_team04_null_safe_person_details.sql`
- `supabase/migrations/20260913165616_team08_second_club_erasure_approver_pilot.sql`
- `supabase/migrations/20260913183313_team08_global_erasure_test_player_context.sql`
- `supabase/migrations/20260913193219_team08_profile_wide_global_erasure.sql`
- `supabase/functions/person-erasure-worker/index.ts`
- `test/team08_roster_lifecycle_test.dart`

## Databas- och säkerhetsgräns

- Vanlig arkivering och initiering kräver `club.memberships.manage` i lagkontext.
- Godkännande kräver klubbscopad `club.memberships.manage` och en annan autentiserad profil.
- Global review/finalize är återkallad för anon/authenticated och uttryckligen endast granted till `service_role`.
- Finalize kräver att den berörda raden saknas i `auth.users`; Auth Admin-radering ska göras av separat serverworker och aldrig av klienten.
- Security-definer-funktionerna ligger i `internal` eller har service-only API-grind, tom `search_path`, explicit auth/current-user-kontroll och revoke/grant.
- Partiella index används för öppna raderingsärenden och transaktionsbundna advisory locks serialiserar personlivscykeln.
- Migrationerna och Auth-workern är driftsatta i det uttryckligen godkända testprojektet `hgcshgunvooyudvrcpig`.

## Verifiering

- `flutter analyze`: inga problem.
- Ett widgettest, ett SQL-kontraktstest och ett modelltest har lagts till.
- Den fulla Flutter-sviten har senare passerat som del av den samlade regressionen.
- Statisk kontroll bekräftar dual control, service-only global review, neutralisering, Auth-existensgrind och frånvaro av hard-delete för roster/eventhistorik.
- Supabase/Postgres-praktikskillen styrde partiella index och transaktionsbundna advisory locks.

## Slutverifiering 2026-09-13

- Avslutning och återaktivering verifierades; spelaren flyttas mellan aktiv trupp och `Tidigare` utan att historiken bryts.
- Klubbanonymisering verifierades med två separata användare. Initiatorn kunde inte godkänna sin egen begäran och en behörig klubbgranskare kunde slutföra den.
- Global kontoradering verifierades genom support-adminflödet och den driftsatta Auth-workern. Det raderade kontot kunde därefter inte logga in.
- Profilomfattande eftermigration säkerställer att samtliga personidentiteter kopplade till profilen anonymiseras, även om äldre data innehåller flera `person_id`.
- Den neutrala historikposten `Tidigare spelare` verifierades på fysisk Android-tablet i korrekt lagkontext.
- TEAM-08:s produktgrindar är stängda. Slutlig juridisk text och policy för eventuell publik namngiven historik ligger kvar som separata krav före extern lansering.
