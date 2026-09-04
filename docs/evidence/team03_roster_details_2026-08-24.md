# TEAM-03 – trupplista och medlemsdetalj

Datum: 2026-08-24  
Status: genomförd; hosted runtime, mobil och desktop/webb verifierade, fysisk tabletgrind återstår

## Levererat

- Trupplistan har textsökning, statusfiltren Alla/Aktiva/Övriga och befintlig sidindelning för stora trupper.
- Telefon öppnar medlemsdetaljen i en snabb bottom sheet. Tablet/desktop använder en tvåpanelsvy där listan ligger kvar.
- Klienten stänger fail-closed för guest, okänd roll eller saknad roster-capability.
- Ny API-projektion returnerar grundläggande lag- och spelaruppgifter till tillåtna roller. Administrativ provenance, assignmentdatum, revision och safeguarding-flagga returneras endast med `club.memberships.manage`.
- Kontaktuppgifter har inte lagts till eftersom nuvarande schema saknar verifierade kontaktfält. Inga fält har uppfunnits eller härletts.

## Filer

- `lib/src/features/roster/roster_surface.dart`
- `lib/src/features/roster/roster_models.dart`
- `lib/src/features/roster/roster_services.dart`
- `lib/src/core/localization/app_strings.dart`
- `supabase/migrations/20260824155142_team03_roster_details.sql`
- `test/team03_roster_details_test.dart`

## Säkerhetsgräns

- Serverfunktionen kräver autentisering och `team.roster.view` eller `club.memberships.manage`.
- Endast player, leader, guardian och club_functionary accepteras; okänd roll ger `role_not_supported`.
- Definer-funktionen har tom `search_path`, fullständigt kvalificerade objekt och explicit revoke/grant.
- TEAM-03-migreringen finns i den uttryckligen godkända testdatabasen `hgcshgunvooyudvrcpig`.

## Verifiering

- `flutter analyze`: inga problem.
- `flutter test test/team03_roster_details_test.dart`: 4/4 passerar.
- Samlad regression för TEAM-01–03: 9/9 passerar. Paginationstestet scrollar uttryckligen till den lazily byggda knappen och är därmed viewport-oberoende.

### Fysisk Mi 9-regression 2026-08-28

- Audit-debugbuild `52E164D7174EBBC40F025FDFE9B16B23947646B91AE0CF1FF1A6EC2D7FF0106B` installerades på Xiaomi Mi 9, Android 10.
- Truppens Alla/Aktiva/Tidigare-filter, dataminimerade personrader och mobil detalj-sheet renderade utan overflow.
- Första körningen hittade en defekt: Android-back från persondetaljen avslutade appen eftersom sheeten låg på den inre sidnavigatorn.
- Sheetens navigator ändrades till root-navigatorn och ett `handlePopRoute`-regressionstest lades till.
- Riktad TEAM-03-körning passerade 4/4 och analysen var ren.
- Korrigerad audit-debugbuild med SHA-256 `682A444638127D754D24568F3B3E53243532D421212AD9C435DC9EA8EFE5DC64` installerades och produktägaren bekräftade fysiskt att Android-back nu stänger detaljen och återgår till Trupp.

### Hosted runtime och desktop/webb 2026-09-01

- `api.list_club_people(uuid,uuid)` och `api.get_roster_person_details(uuid,uuid,uuid)` finns i testdatabasen.
- `authenticated` har execute; `anon` och `PUBLIC` saknar execute på båda RPC:erna.
- Den installerade detaljfunktionen innehåller både capabilitygrind och rollminimering.
- Tidigare fysisk REL-02-verifiering bekräftade begränsad Trupp för player/guardian på desktop/webb utan administrativa åtgärder.
- Omsprungen TEAM-03-regression passerade 4/4 och riktad analys gav inga problem.

## Kvarstående grindar

- Fysisk tablet/desktop-verifiering av tvåpanelsvyn återstår.
- En separat fysisk tabletpassering krävs innan TEAM-03 markeras helt klar.
