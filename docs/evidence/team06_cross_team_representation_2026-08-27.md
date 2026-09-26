# TEAM-06 – behörighet att representera andra lag

Datum: 2026-08-27  
Status: slutförd; hosted runtime och fysisk Android-tabletgrind verifierade

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
- Migrationerna är applicerade i det uttryckligen godkända testprojektet `hgcshgunvooyudvrcpig`.

## Verifiering

- `flutter analyze`: inga problem.
- TEAM-05/06: 7/7 tester passerar.
- Samlad TEAM-03–06 och S04-regression: 19/19 passerar.
- Testerna verifierar typer, giltighetsformer, granskningsdag, överlappslås, frånvaro av home-team-/eventmutation och eventtidskontroll.
- Aktuell Supabase/Postgres-dokumentation för funktionsprivilegier, tidsintervall och indexering kontrollerades. Postgres-praktikskillen styrde valet av partiella sammansatta index och transaktionsbundet advisory lock.

## Hosted och fysisk slutverifiering 2026-09-13

- En särskild kandidatprojektion ersatte den klubbomfattade generella trupplistan. Lagledaren ser endast minsta nödvändiga uppgifter för aktiva spelare i klubbens andra lag; åtkomst kräver managementbehörighet i mållaget.
- Tomt kandidatresultat och serverfel visas ovanpå representationspanelen och kan alltid läsas.
- Fysisk test ledde till att en andra lagyta skapades genom det nya flödet: alla ledare kan begära ett lag, klubbfunktionär kan godkänna eller avslå, och väntande antal visas på lagväljaren och menyvalet.
- Fysisk Android-tablettest: kandidat från Thomas lag visades, säsongsbunden utvecklingsrepresentation skapades och listades som aktiv, ordinarie spelare låg kvar i Thomas lag och representationen kunde avslutas.
- Två riktiga runtimefel hittades och korrigerades: tvetydig `result` i lagbegärans beslut och tvetydig `starts_at` i representationskommandot. Båda verifierades med helt återställda hosted transaktioner; skapa-kommandot returnerade ett eligibility-ID.
- Database Advisor passerade utan nya TEAM-06-/RLS-varningar. Endast den kända Auth-inställningen för läckta lösenord återstår.
- Androidbygget kompilerar och installerar. Den riktade Fluttertestprocessen fastnade utan utskrift i den lokala Windowsmiljön och avbröts; tidigare TEAM-06-regression samt den fysiska hosted-grinden är gröna.
