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
3. **Formationer med krav** – databasen klar 2026-11-21: `20270408090000_team_formations.sql` (`core.team_formations`, med `api.list_team_formations`, `api.save_team_formation` och `api.delete_team_formation`). Test: `supabase/tests/team_formations.local.mjs`.
   - En formation har ett namn, linjer (`4-3-3`), ett matchformat (`3v3`–`11v11`) och, per plats, en valfri position ur sportens lista och upp till sex krav `{attribute, weight}`, där weight 1 = viktig och 2 = mycket viktig.
   - Platserna har appens koder: `GK` (finns inte i 3v3), sedan linje för linje från eget mål, vänster till höger: `1A`, `1B` … `2A` … Tacticsboard ställer upp en formations spelare i samma ordning, så koderna gäller i båda.
   - En plats allmänna position följer linjen: den första av flera linjer försvarar, den sista anfaller och resten är mittfält.
   - Upp till 30 formationer per lag, och namnen är unika i laget. Sparar två samtidigt får den andra `PT409 stale_revision`.
   - Bara de som ser egenskaperna (lagets ledare) ser formationerna. Krav på en av lagets egna egenskaper som har tagits bort försvinner ur formationen.
   - Platsernas exakta placering på planen sparas inte. Den räknas fram från linjerna, som idag i både appen och Tacticsboard.
   - Formationerna skapas och redigeras i steg 5 (Tacticsboard) och väljs i steg 6 (appen).
4. **Förslagsfunktionen** – databasen klar 2026-11-21: `20270409090000_lineup_suggestion.sql` med `api.suggest_lineup(club, team, formation_id, lines, match_format, candidate_ids, locked)`. Test: `supabase/tests/lineup_suggestion.local.mjs`.
   - **Formation:** en sparad formation (`formation_id`), eller bara linjer och format. Utan sparad formation har platserna inga krav utöver sin linje, som i appens laguttagning idag.
   - **Urval:** `candidate_ids` är de spelare som får väljas, t.ex. de kallade. Utan urval används lagets alla spelare. En spelare från ett annat lag måste kunna representera laget.
   - **Låsta platser:** `locked` är `{kod: person_id}`. De platserna behåller sin spelare, och resten föreslås.
   - **Poäng per spelare och plats:**
     - Platsens position som spelarens huvudposition ger 10, som en annan av spelarens positioner 7.
     - Annars räknas platsens linje: som spelarens huvudgrupp 5, som en annan grupp 3. Om platsen inte anger någon position blir det 10 respektive 6.
     - Målvakt: en plats i mål för någon som inte är målvakt ger −10, och en huvudmålvakt ute på planen −10.
     - Krav med vikt w (1 viktig, 2 mycket viktig): en styrka ger +3w och ett utvecklingsområde −2w.
   - **Fördelning:** spelarna placeras så att lagets totala poäng blir högst (ungersk metod), inte genom att ta den bästa platsen först. Är spelarna färre än platserna blir några platser tomma.
   - **Svaret:** för varje plats kommer spelaren med poäng, hur positionen passar (`main`, `other`, `group`, `none`), vilka styrkor och utvecklingsområden som slog in, och de tre bästa alternativen. Dessutom kommer de spelare som blev över (`bench`).
   - **Positioner:** de hämtas från lagets egna uppgifter, och för en spelare från ett annat lag från hemlaget. Egenskaperna är lagets egna, så en sådan spelare har inga här.
5. **Tacticsboard** – byggt och provat lokalt mot testdatabasen 2026-11-21 (lag J: spara en formation med krav, Föreslå spelare). Under *Trupp → Formation* i ett projekt kopplat till ett TeamZone-lag, för lagets ledare:
   - **Formationsvalet** visar *Lagets formationer* först och sedan *Vanliga formationer*.
   - **Föreslå spelare** (bara för hemmalaget) anropar `api.suggest_lineup` och ställer upp spelarna. Spelare som redan står på planen flyttas, saknade hämtas ur truppen, och truppspelare som inte kom med tas bort. Förslaget listas med varför varje spelare valdes: huvudposition och de styrkor och utvecklingsområden som slog in.
   - **Krav per position** öppnar en redigerare med alla platser (MV, VB, MB …). Varje plats får en valfri position och upp till sex egenskaper, var och en *Viktig* eller *Mycket viktig*. Den sparar en ny formation för laget, eller ändrar och tar bort en sparad.
   - **Utan klubb-id:** Tacticsboard skickar bara lagets id. `20270410090000_formations_by_team.sql` låter funktionerna hitta klubben från laget.
   - **Kod:** `webtools/lib/tactics/lineup.ts`, `attributes.ts`, `components/tactics/use-team-formations.ts`, `panels/TeamLineup.tsx` och `panels/FormationRequirements.tsx`. Test: `tests/tactics-lineup.test.ts`.
6. **Appen, startelvan** – byggt 2026-11-21. Gäller *Match → Uppställning* för lagets ledare.
   - **Formationsvalet** visar lagets formationer för matchens format (t.ex. "Press (3-2-1)") före de vanliga.
   - **Föreslå** ersätter spelarna på planen med förslaget. Förslagets spelare tas bort från bänken. Under planen visas *Därför föreslås de*, med huvudposition och de styrkor och utvecklingsområden som slog in.
   - **Urval:** de kallade som inte har tackat nej. Om ingen är kallad används alla som inte har tackat nej. Spelare som inte längre får spela för laget hoppar databasen över.
   - **Databas:** `20270411090000_event_lineup_suggestion.sql`, med `api.list_event_team_formations` och `api.suggest_event_lineup`. Båda utgår från matchen.
   - **Kod:** `lib/src/features/match_workspace/lineup_suggestion_services.dart`, `match_lineup_suggestion.dart` och `match_lineup_editor.dart`. Test: `test/match_lineup_suggest_test.dart`.
