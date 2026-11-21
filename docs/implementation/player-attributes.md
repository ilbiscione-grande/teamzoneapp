# Spelaregenskaper och förslag på uppställning

Beslutat med produktägaren 2026-11-21.

Ledarna bockar för spelarnas styrkor och utvecklingsområden i TeamZone-truppen. I en formation anger man vilka egenskaper som är viktiga på varje position. Tacticsboard och appens laguttagning (startelvan) kan sedan föreslå vilka spelare som passar var.

## Beslut

- **Bara bockar, inga betyg.** Varje egenskap hos en spelare är *styrka*, *utvecklingsområde* eller ingenting. En egenskap kan inte vara båda samtidigt. Siffror (1–5) valdes bort tills vidare, och kan läggas till senare utan att något som redan är ifyllt går förlorat.
- **Bara lagets ledare ser egenskaperna** (`team.roster.manage`). Spelare och vårdnadshavare ser dem inte.
- **Katalog:** en fast lista per sport (`core.sport_attributes`, uppdelad på fysik, teknik, spelförståelse och mentalt) plus högst 15 egna per lag (`core.team_attributes`).
- **Per lag:** bedömningen gäller spelaren i det laget. När spelarrollen i laget upphör raderas spelarens egenskaper där.
- **Förslagen räknas ut på ett ställe,** i databasen, så att Tacticsboard och appen alltid föreslår samma sak och egenskaperna aldrig lämnar servern för någon som inte är ledare.

## Steg

1. **Databas** – klart 2026-11-21: `20270407090000_player_attributes.sql`. Den innehåller `api.get_team_player_attributes`, `api.set_player_attributes`, `api.save_team_attribute` och `api.delete_team_attribute`. Test: `supabase/tests/player_attributes.local.mjs`.
2. **Appen, spelarprofilen** – klart 2026-11-21: fliken *Egenskaper* på en spelares profil, för ledare. Varje bock sparas direkt, och lagets egna egenskaper läggs till, byter namn eller tas bort därifrån. Kod: `lib/src/features/roster/player_attributes_services.dart` och `player_attributes_tab.dart`.
3. **Formationer med krav:** varje plats i en formation får en position och de egenskaper som är viktiga där, var och en som *viktig* eller *mycket viktig*. Formationerna sparas per lag så att Tacticsboard och appen delar dem.
4. **Förslagsfunktionen** (en funktion i databasen): varje spelare får poäng per plats. Positionen ger poäng (huvudposition, annan position, samma grupp), en styrka ger plus och ett utvecklingsområde minus, viktat efter kravet. Sedan fördelas spelarna så att laget som helhet får högst poäng. Det går att låsa spelare och få resten föreslaget, och att begränsa urvalet (t.ex. till de som är kallade).
5. **Tacticsboard:** välj eller skapa en formation, ange kraven per plats och tryck *Föreslå spelare*. Förslaget går att ändra fritt.
6. **Appen, startelvan:** samma *Föreslå* i matchens laguttagning, som bara använder kallade och anmälda spelare.
