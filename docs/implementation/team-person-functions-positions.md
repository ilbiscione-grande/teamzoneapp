# Titlar och spelarpositioner

2026-09-29

Personer kan ha titlar (i UI "Titel", t.ex. huvudtränare, assisterande
tränare, lagledare) och spelarpositioner per lag. Uppgifterna är beskrivande
och ändrar aldrig behörigheter; behörighet styrs av rollen (Ledare/Spelare)
och dess capability grants.

## Regler

- **Titlar hör till ledarroller**, positioner till spelarroller. Det
  kontrolleras i databasen (`titles_need_leader_role`,
  `positions_need_player_role`), inte bara i UI. Den som har båda rollerna
  kan ha båda.
- **Rensas när rollen upphör.** En trigger på `core.assignments` tömmer
  positioner när spelarrollen avslutas och titlar när sista ledarrollen
  avslutas — oavsett flöde (rolländring, borttagning, arkivering, radering).
- **Två nivåer av positioner per idrott.** `core.sport_positions` innehåller
  övergripande positioner (målvakt, försvarare, mittfältare, anfallare) och
  detaljerade med förälder (mittback → försvarare). Väljs en detaljerad
  position döljs den övergripande i sammanfattningen.
- **Idrott per lag.** `core.teams.sport` (fotboll, handboll, annan idrott)
  väljer katalog. Sätts under Översikt → Redigera lagprofil → Idrott, men bara
  av klubbens administratörer (klubbskopad `club.memberships.manage`, sedan
  `20260930170000_team_sport_club_admin_only.sql`); övriga ser idrotten
  skrivskyddat. Byte
  av idrott tar bort positioner som inte finns i den nya katalogen; lagets
  egna benämningar behålls. "Annan idrott" har bara egna benämningar.
- **Egna benämningar.** Upp till fem egna titlar och fem egna positioner per
  person och lag (1–40 tecken).

## Var det syns

- Laget → Trupp → Ledare och roller: titlar per ledare; tryck på raden för att
  ändra (även den egna).
- Personprofilen: "Titel", "Position" eller "Titel och position" beroende på
  roll.
- Lagöversiktens ledarlista och Deltagare-fliken visar ledarens titlar.
  Titlarna läses via `list_team_roles`; den som saknar truppbehörighet ser
  bara namnen.

## Databas och API

- `20260929101319_team_person_functions_positions.sql` (Codex): tabell
  `core.team_person_details`, `api.set_team_person_details` (v1).
- `20260929140000_team_titles_positions_by_sport.sql`: idrott, katalog, egna
  benämningar, rollkontroll, rensning, `api.set_team_person_details_v2`,
  `api.set_team_sport`. `list_team_roles` returnerar även `sport`,
  `position_catalog`, `custom_titles` och `custom_positions`.
- Kolumnen heter fortfarande `functions` i databasen; appen kallar dem titlar.
- v1 fungerar fortfarande för äldre klienter, lämnar egna benämningar orörda
  och följer samma rollregler.

## Verifiering

- `node supabase/tests/team_roles.local.mjs --details`
- `flutter test test/team09_team_roles_test.dart`
