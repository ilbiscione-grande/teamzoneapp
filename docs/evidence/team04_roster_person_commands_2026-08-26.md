# TEAM-04 – skapa och redigera rosterperson

Datum: 2026-08-26  
Status: lokalt genomförd, runtime-/fysisk grind återstår

## Levererat

- Behörig användare kan lägga till en person från truppens Hantera-meny.
- Befintlig person kan öppnas i ett förifyllt redigeringsformulär direkt från trupplistan.
- Formulären har längdvalidering, pending-/double-submit-skydd, neutralt fel och varning innan osparade ändringar kastas.
- Create skapar `core.persons`, klubbprofil och lagrepresentation i samma databastransaktion.
- Normaliserat namn plus åldersklass skyddas mot samtidiga dubbletter i samma lag med transaktionslås.
- Update kräver aktuell klubbpersonsrevision och ändrar endast `core.club_people`.
- `core.persons`, `core.profiles` och kontots globala identitet skrivs aldrig över.

## Filer

- `lib/src/features/roster/roster_surface.dart`
- `lib/src/features/roster/roster_models.dart`
- `lib/src/features/roster/roster_services.dart`
- `lib/src/core/localization/app_strings.dart`
- `supabase/migrations/20260826190142_team04_roster_person_commands.sql`
- `test/team04_roster_person_form_test.dart`

## Säkerhets- och robusthetsgräns

- Båda kommandona kräver `club.memberships.manage` i angiven klubb-/lagkontext.
- Team, klubbperson och aktiv lagrepresentation verifieras server-side.
- Idempotency sparas per actor, command type och nyckel; mutationer auditloggas.
- Update låser klubbposten och avvisar stale revision.
- Definer-funktioner använder tom `search_path`; den nya API-funktionen har explicit revoke/grant.
- Liveprojektet `hgcshgunvooyudvrcpig` har inte ändrats.

## Verifiering

- `flutter analyze`: inga problem.
- `flutter test test/team04_roster_person_form_test.dart`: 5/5 passerar, inklusive create, edit, revision och osparade ändringar.
- Samlad TEAM-01–04/Auth-regression före det sista separata edit-testet: 17/17 passerar.
- Nuvarande Supabase-dokumentation för databasfunktioner och 2026 års Data API-/grantförändring kontrollerades innan implementationen.

## Kvarstående grindar

- Migrationen är lokal och har inte körts mot Supabase live.
- Docker/lokal PostgreSQL saknas, så SQL-runtime och advisor-körning återstår.
- Fysisk phone/tablet/desktop-verifiering av create/edit och back-varningen återstår.
