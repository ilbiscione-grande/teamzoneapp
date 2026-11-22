# Enkäter i Säsongsplanering

**Status: byggd 2026-11-22.** Beslutad av produktägaren samma dag, inför individuella spelarsamtal.

Lagets ledare skriver en kort enkät, delar den med spelarna och sparar svaren som underlag för samtalen och spelarens utveckling.

## Hur det fungerar

- **Var:** Säsongsplanering → fliken *Enkäter*. En ny enkät är tom eller utgår från mallen *Inför spelarsamtal* (nio frågor: fyra skalor 1–5, tre fritext, en flerval och en avslutande fråga). Mallen kan ändras fritt innan den sparas.
- **Frågetyper:** kort svar, längre svar, skala 1–5 (med valfria ord för 1 och 5), ett alternativ, flera alternativ. Högst 30 frågor; en fråga kan vara obligatorisk.
- **Läge:** utkast → öppen → stängd (och öppen igen). Länkarna tar bara emot svar när enkäten är öppen. Frågorna låses när det första svaret har kommit; rubrik och inledning går fortfarande att ändra.
- **Personliga länkar:** ledaren väljer spelare ur truppen (alla förvalda). Varje spelare får en egen länk, och svaren kopplas direkt till spelaren. Spelare med konto får en notis (push och notislistan, `team.survey.invited.v1`) när enkäten är öppen, en gång per länk. Övriga får länken kopierad av ledaren. Spelaren kan öppna länken igen och ändra sina svar så länge enkäten är öppen.
- **Öppen länk (valfri):** en gemensam länk där man skriver sitt namn. Svaren kan kopplas till en spelare i efterhand under *Svar*. Högst 10 svar per timme från samma adress och 300 per enkät.
- **Skicka länken (tillagt 2026-11-22):** tryck på en spelare under *Dela* för att skicka länken med WhatsApp, sms eller e-post, direkt till spelarens nummer eller adress när TeamZone har dem (samma kontaktuppgifter som lagets ledare ser på profilen). *Fler appar* öppnar telefonens egen dela-meny (Android-appen och mobilwebbläsare). Meddelandet och länken kan också kopieras. Den öppna länken delas på samma sätt, till exempel i lagets gruppchatt.
- **Inbjudan i appen:** en spelare med konto ser sina obesvarade enkäter som ett kort på startsidan, med knappen *Svara*. *Påminn i appen* skickar en påminnelse (`team.survey.reminded.v1`, push och notislistan) till dem med konto som inte har svarat, högst en gång per länk på 12 timmar.
- **Svar:** per person, och alla svar som tabell att klistra in i ett kalkylark.
- **Statistik:** antal svar, andel besvarade personliga länkar och snittet på skalfrågorna. Skalfrågorna jämförs med varandra (högst och lägst). Per fråga visas fördelningen med antal och andel, alternativen sorterade efter antal och fritext med namn. En spelare kan väljas för att se sina svar mot lagets. Spelarens profil har fliken *Enkäter* med spelarens svar, senaste först, med lagets snitt bredvid varje skalfråga.
- **Svarssidan** ligger i Webtools, `/enkat/<token>` (webtools.teamzoneapp.se i produktion), utan inloggning. Den publika webbplatsen användes inte eftersom den fortfarande läser testdatabasen. Sidans server läser och skriver med den hemliga nyckeln genom `api.public_get_team_survey` och `api.public_submit_team_survey`, som bara `service_role` får anropa. Svaren skickas med en Next-serveråtgärd (Next kontrollerar ursprunget).

## Behörighet och data

- Den som har `development.manage` i laget och modulen Säsongsplanering läser (`internal.tdp_team_club`). Att ändra kräver att modulen inte är skrivskyddad (`internal.tdp_can_edit`).
- Spelare och vårdnadshavare ser aldrig andras svar. En personlig länk visar bara sina egna tidigare svar.
- Svaren finns kvar tills ledarna tar bort svaret eller enkäten (då försvinner allt). Svaren finns kvar även om spelaren lämnar laget.
- Tabeller: `core.team_surveys`, `core.team_survey_invites`, `core.team_survey_responses`. Migrationer `20270417090000_team_surveys.sql`, `20270417090001_team_survey_notifications.sql`, `20270418090000_team_survey_sharing.sql` (kontakt, påminnelse, mina enkäter, lagets snitt) och `20270418090001_team_survey_reminder_notifications.sql`. Telefon och e-post på länkarna visas bara för den som leder laget (`internal.actor_leads_team`). Androids dela-meny går genom kanalen `teamzone/share` i `MainActivity.kt`, webben genom Web Share (`lib/src/core/share/`). Test: `supabase/tests/team_surveys.local.mjs`.

## Kvar att avgöra

- Om vårdnadshavare till yngre spelare också ska få notisen, se kortet på startsidan och få länken skickad till sitt nummer.
- Hur länge svaren ska sparas, och om det ska stå i integritetstexten.
- Koppling till den kommande IDP:n (individuell utvecklingsplan).
