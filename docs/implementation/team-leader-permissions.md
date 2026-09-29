# Behörigheter per ledare

2026-09-29

Behörighet styrs av capability grants på personens ledarroll i laget, aldrig
av rollnamnet eller titeln. Den breda `event.manage` är uppdelad så att olika
ledare kan ansvara för olika delar.

## Behörigheter i panelen

| Grupp | Behörighet | Capability |
|---|---|---|
| Laget | Trupp och medlemmar | `team.roster.manage` |
| Laget | Ledare och behörigheter | `team.leaders.manage` |
| Event | Skapa och flytta event | `event.manage` (oförändrad betydelse) |
| Event | Kallelser | `event.squad.manage` |
| Event | Närvaro / sen närvarorättelse | `event.attendance.manage` / `event.attendance.correct_late` |
| Event | Material, uppgifter och filer | `event.logistics` |
| Träning | Träningsupplägg | `training.plan` |
| Match | Matchplan och taktik | `match.plan` |
| Match | Matchläge och resultat | `match.live` |
| Övrigt | Spelarutveckling / Publicera | `development.manage` / `publication.manage` |

Förberedelser: träningsfokus och träningsanteckning kräver `training.plan`,
matchförberedelsen `match.plan`, allt annat (material, uppgifter, agenda,
filer, övriga anteckningar) `event.logistics`. Kontrollen sitter i triggers på
tabellerna och gäller därför alla kommandon.

## Mallar

Huvudtränare (allt), Assisterande tränare, Lagledare (inkl. Matchläge, utan
träningsupplägg och taktik), Målvakts- och fystränare, Ledare (standard).
En titel föreslår en mall men tillämpas först när man trycker Använd och
sparar. Mallen sparas i `team_person_details.permission_template`; avviker
urvalet visas "Anpassad".

## Regler (kontrolleras i databasen)

- Panelen kräver `team.leaders.manage` (klubbfunktionärer har den alltid).
- Man kan bara ge eller ta bort behörigheter man själv har.
- Man kan inte ta bort sin egen `team.leaders.manage`; laget måste alltid ha
  någon som har den.
- Bara innehavare av `team.leaders.manage` kan göra någon till ledare, oavsett
  väg (rollkommando, godkänd ansökan, rollbyte i godkännande).
- Samtidiga ändringar: klienten skickar det urval den såg; avviker det nuvarande
  avvisas ändringen (`stale_permissions`). Allt loggas i `audit.command_events`.

## Utrullning

Alla som har `event.manage` i dag får de uppdelade behörigheterna på samma
nivå, så inget ändras för befintliga ledare. Nya ledare får standardpaketet
utan `team.leaders.manage`. Klubbfunktionärer (klubbnivå) får hela panelen.
Befintliga ledare kan därför inte längre göra andra till ledare förrän en
klubbfunktionär ger dem mallen Huvudtränare eller behörigheten.

## Filer

- `supabase/migrations/20260929160000_team_leader_permissions.sql`
- `lib/src/features/roster/leader_permissions.dart` (panelen)
- Test: `node supabase/tests/leader_permissions.local.mjs`,
  `flutter test test/team09_team_roles_test.dart test/prep01_event_preparation_test.dart`
