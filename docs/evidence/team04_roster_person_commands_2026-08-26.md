# TEAM-04 – skapa och redigera rosterperson

Datum: 2026-08-26  
Status: slutförd; hosted runtime samt fysisk webb-, Android- och tabletgrind verifierade

## Levererat

- Behörig användare kan lägga till en person från truppens Hantera-meny.
- Befintlig person kan öppnas i ett förifyllt redigeringsformulär direkt från trupplistan.
- Formulären har längdvalidering, pending-/double-submit-skydd, neutralt fel och varning innan osparade ändringar kastas.
- Personformuläret kräver födelseår via årsväljare. Exakt födelsedatum är en valfri komplettering via kalender och kan läggas till eller tas bort senare utan att ett påhittat datum lagras.
- Create skapar `core.persons`, klubbprofil och lagrepresentation i samma databastransaktion.
- Namn och åldersklass är beskrivande uppgifter, inte personidentitet. Flera personer i samma lag får därför ha samma värden och särskiljs av egna person-ID:n.
- Update kräver aktuell klubbpersonsrevision och ändrar endast `core.club_people`.
- `core.persons`, `core.profiles` och kontots globala identitet skrivs aldrig över.
- Exakt födelsedatum lagras som privat `date` på klubbpersonen och exponeras endast i capabilityskyddad managementprojektion; generell trupplista visar bara födelseår.

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
- TEAM-04-migreringen finns i den uttryckligen godkända testdatabasen `hgcshgunvooyudvrcpig`.

## Verifiering

- `flutter analyze`: inga problem.
- `flutter test test/team04_roster_person_form_test.dart`: 5/5 passerar, inklusive create, edit, revision och osparade ändringar.
- Samlad TEAM-01–04/Auth-regression före det sista separata edit-testet: 17/17 passerar.
- Nuvarande Supabase-dokumentation för databasfunktioner och 2026 års Data API-/grantförändring kontrollerades innan implementationen.

### Hosted runtime 2026-09-01

- Create- och update-RPC finns i testdatabasen och kan exekveras av `authenticated`; `anon` och `PUBLIC` saknar execute.
- Installerad create-funktion innehåller `club.memberships.manage` och advisory lock; installerad update-funktion innehåller expected-revision-grinden.
- Ingen persondata skapades eller ändrades under runtimekontrollen.
- Omsprungen TEAM-04-regression passerade 6/6 och riktad analys gav inga problem.

### Fysisk webbverifiering 2026-09-01

- Produktägaren skapade en rosterperson via `Laget → Trupp → Hantera → Lägg till person` och bekräftade att personen visades i truppen.
- Befintlig rosterperson öppnades och redigerades; den sparade ändringen visades korrekt.
- Redigering lämnades med osparad ändring och varningen för osparade ändringar fungerade.

## Kvarstående grindar

- Webb, telefon och tablet är fysiskt godkända för create/edit och osparat-skydd.
- Produktkorrigering 2026-09-12: den felaktiga unikhetsregeln för normaliserat namn + åldersklass tas bort genom `20260912183346_team04_allow_same_name_and_age_class.sql`. Retry-säkerhet behålls genom befintlig kommandospecifik idempotens.
- Migrationen är applicerad i den godkända testdatabasen och lokal/fjärr migrationshistorik matchar. Produktägaren verifierade därefter fysiskt på Xiaomi Mi 9 att en andra separat spelare med exakt samma namn och åldersklass kan skapas.
- Mobilens create- och editflöde är verifierat på Xiaomi Mi 9: en person skapades, en av två personer med samma namn/år redigerades utan att den andra ändrades och sparad data visades i truppen.
- Fysisk test hittade att Android-back kunde kringgå formulärets `PopScope`. Produktskalet använder nu `Navigator.maybePop()` i stället för en tvingad router-pop, så den aktiva sidan får stoppa navigeringen. 26/26 riktade TEAM-03/04-, skal- och navigationsregressioner passerade; produktägaren verifierade därefter både **Avbryt** och **Kasta** på Mi 9.
- Efter lokal rosterredigering verifierade produktägaren att profildrawern fortfarande visade kontots ursprungliga globala namn. Den lokala klubb-/lagprofilen skriver alltså inte över användarens globala identitet.
- På fysisk Android-tablet verifierade produktägaren först skapande med endast födelseår och därefter komplettering med månad och dag. Trupplistan fortsatte visa endast året medan exakt datum hölls i behörig detalj-/redigeringsvy.
- Den slutliga riktade TEAM-04-sviten passerade 16/16. Full Flutter-regression passerade 372 tester och identifierade endast en saknad engelsk översättning för den redan testade TEAM-03-texten `Tillbaka till truppen`; översättningsposten lades till utan ändring av TEAM-04-flödet.
- Supabase Database Advisor passerade utan TEAM-04-/schemavarningar. Endast den sedan tidigare kända projektinställningen för läckta lösenord återstår.
