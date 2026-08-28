# TEAM-06 – behörighet att representera andra lag

Datum: 2026-08-27  
Status: lokalt genomförd, runtime-/fysisk grind återstår

## Levererat

- Ledare kan administrera utvecklingsspel, dispens, lån och gästspel för det valda mållaget.
- Giltighet kan anges som säsong, valt slutdatum eller tills vidare.
- Säsong lagras med explicit säsongsslut och upphör tidsmässigt utan batchjobb.
- Tillsvidare kräver en granskningsdag. Efter den dagen är representationen `review_due` och godtas inte för senare event innan den förnyas.
- Skapa/lista/avsluta använder capability, tenantkontroll, idempotens, revision och audit.
- Samtidiga överlapp för samma person och mållag serialiseras med transaktionsbundet advisory lock och avvisas.
- Ordinarie `team_assignments` ändras aldrig. Historiska event, laguttagningar och fakta skrivs inte om.
- `person_eligibility_at_event` validerar både start, slut och granskningsdag mot eventets `starts_at`.

## Filer

- `lib/src/features/roster/roster_surface.dart`
- `lib/src/features/roster/roster_models.dart`
- `lib/src/features/roster/roster_services.dart`
- `lib/src/core/localization/app_strings.dart`
- `supabase/migrations/20260827044300_team06_cross_team_representation.sql`
- `test/team06_play_eligibility_test.dart`

## Databas- och säkerhetsgräns

- Mutation kräver `club.memberships.manage` i mållagets klubb-/lagkontext.
- Personen måste ha en aktiv ordinarie lagrepresentation vid start och mållaget måste vara ett annat aktivt lag i klubben.
- Periodformen är databaskontrollerad för season/fixed/indefinite.
- Partiella sammansatta index stöder aktiva lag-/period- och personfrågor.
- Definer-funktionerna ligger i `internal`, använder tom `search_path` och har explicit revoke/grant.
- Liveprojektet `hgcshgunvooyudvrcpig` har inte ändrats.

## Verifiering

- `flutter analyze`: inga problem.
- TEAM-05/06: 7/7 tester passerar.
- Samlad TEAM-03–06 och S04-regression: 19/19 passerar.
- Testerna verifierar typer, giltighetsformer, granskningsdag, överlappslås, frånvaro av home-team-/eventmutation och eventtidskontroll.
- Aktuell Supabase/Postgres-dokumentation för funktionsprivilegier, tidsintervall och indexering kontrollerades. Postgres-praktikskillen styrde valet av partiella sammansatta index och transaktionsbundet advisory lock.

## Kvarstående grindar

- Migrationen är lokal och har inte körts mot Supabase live.
- Docker/lokal PostgreSQL saknas, så SQL-fixtures, `EXPLAIN` och advisors återstår.
- Fysisk verifiering av create/list/end på phone/tablet/desktop återstår.
