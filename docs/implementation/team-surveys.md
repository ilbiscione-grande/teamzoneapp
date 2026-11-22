# Enkäter i Säsongsplanering

**Status: byggd 2026-11-22.** Beslutad av produktägaren samma dag, inför individuella spelarsamtal.

Lagets ledare skriver en kort enkät, delar den med spelarna och sparar svaren som underlag för samtalen och spelarens utveckling.

## Hur det fungerar

- **Var:** Säsongsplanering → fliken *Enkäter*. En ny enkät är tom eller utgår från mallen *Inför spelarsamtal* (nio frågor: fyra skalor 1–5, tre fritext, en flerval och en avslutande fråga). Mallen kan ändras fritt innan den sparas.
- **Frågetyper:** kort svar, längre svar, skala 1–5 (med valfria ord för 1 och 5), ett alternativ, flera alternativ. Högst 30 frågor; en fråga kan vara obligatorisk.
- **Läge:** utkast → öppen → stängd (och öppen igen). Länkarna tar bara emot svar när enkäten är öppen. Frågorna låses när det första svaret har kommit; rubrik och inledning går fortfarande att ändra.
- **Personliga länkar:** ledaren väljer spelare ur truppen (alla förvalda). Varje spelare får en egen länk, och svaren kopplas direkt till spelaren. Spelare med konto får en notis (push och notislistan, `team.survey.invited.v1`) när enkäten är öppen, en gång per länk. Övriga får länken kopierad av ledaren. Spelaren kan öppna länken igen och ändra sina svar så länge enkäten är öppen.
- **Öppen länk (valfri):** en gemensam länk där man skriver sitt namn. Svaren kan kopplas till en spelare i efterhand under *Svar*. Högst 10 svar per timme från samma adress och 300 per enkät.
- **Svar:** per person och per fråga (snitt och fördelning för skalor, antal per alternativ, fritext med namn). Spelarens profil har fliken *Enkäter* med spelarens svar, senaste först.
- **Svarssidan** ligger i Webtools, `/enkat/<token>` (webtools.teamzoneapp.se i produktion), utan inloggning. Den publika webbplatsen användes inte eftersom den fortfarande läser testdatabasen. Sidans server läser och skriver med den hemliga nyckeln genom `api.public_get_team_survey` och `api.public_submit_team_survey`, som bara `service_role` får anropa. Svaren skickas med en Next-serveråtgärd (Next kontrollerar ursprunget).

## Behörighet och data

- Den som har `development.manage` i laget och modulen Säsongsplanering läser (`internal.tdp_team_club`). Att ändra kräver att modulen inte är skrivskyddad (`internal.tdp_can_edit`).
- Spelare och vårdnadshavare ser aldrig andras svar. En personlig länk visar bara sina egna tidigare svar.
- Svaren finns kvar tills ledarna tar bort svaret eller enkäten (då försvinner allt). Svaren finns kvar även om spelaren lämnar laget.
- Tabeller: `core.team_surveys`, `core.team_survey_invites`, `core.team_survey_responses`. Migrationer `20270417090000_team_surveys.sql` och `20270417090001_team_survey_notifications.sql`. Test: `supabase/tests/team_surveys.local.mjs`.

## Kvar att avgöra

- Om vårdnadshavare till yngre spelare också ska få notisen.
- Hur länge svaren ska sparas, och om det ska stå i integritetstexten.
- Koppling till den kommande IDP:n (individuell utvecklingsplan).
