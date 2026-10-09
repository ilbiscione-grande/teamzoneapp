# Närvaroexport till laget.se (tillfällig funktion)

**Status:** tillfällig. Funktionen ska tas bort ur appen med tiden och är därför
byggd som en fristående modul. Den har ett fåtal markerade krokar i befintlig kod
och ett eget databasschema. Se [Borttagning](#borttagning).

Teamzone skapar en UTF-8-kodad JSON-fil för en avslutad aktivitet. Filen
läses av den fristående Playwright-prototypen, som registrerar närvaron i
laget.se (verifierad mot laget.se 2026-10-08). Teamzone loggar aldrig in på
laget.se, utför ingen överföring och lagrar inga inloggningsuppgifter.

## Arkitektur

| Del | Fil | Ansvar |
| --- | --- | --- |
| A. Generell exporttjänst | `lib/src/features/attendance_export/export_basis.dart`, `export_models.dart` | Bygger ett exportunderlag från befintliga `api.get_event_details` och `api.get_event_squad`. Känner inte till laget.se-formatet. |
| B. Adapter för laget.se | `lib/src/features/attendance_export/laget_se/laget_se_adapter.dart` | Matchar medlemmar via person-ID (aldrig via namn), översätter status, validerar (`validateLagetSeExport`), genererar JSON och kontrollerar kontraktet (`lagetSeContractErrors`). |
| C. Exportgränssnitt | `ui/attendance_export_page.dart`, `ui/laget_se_settings_page.dart` | Visar sammanställning, saknade kopplingar, bekräftelse och status. Hanterar också kopplingar. |
| Flöde och fil | `export_runner.dart` | Kör validering, sparar filen via befintliga `file_picker` (nedladdning på webben, "spara som" på Android/iOS, ingen temporär kopia) och loggar exporten. |
| Lagring | `export_services.dart`, `supabase/migrations/20261013090000_attendance_export_laget_se.sql` | Schemat `attendance_export` och RPC:erna `api.attendance_export_*`. |
| Ingång | `attendance_export.dart` | Det enda bibliotek resten av appen importerar: funktionsflagga, tjänster och krokfunktioner. |

En ny mottagare blir en ny adapter bredvid `laget_se/` plus ett nytt värde i
`provider`-kontrollerna. Närvaromodellen behöver inte ändras.

## Import av medlemslista

Laget.se-ID behöver inte skrivas in för hand.

1. Kör `npm run members -- --url <valfri aktivitet>` i synkverktyget (`C:\Dev\laget-playwright`).
   Det skriver `data/laget_members.json` med lagets spelare och ledare (namn, roll, laget.se-ID), men ingen närvaro. Format:
   `{"format":"laget_se_members","version":1,"teamSlug":…,"sourceActivityId":…,"readAt":…,"members":[{"id","name","role"}]}`
2. Välj Integrationer → laget.se → **Importera medlemslista från laget.se**. Filen läses bara i minnet.
3. Teamzone (`laget_se/laget_se_member_import.dart`) jämför listan med truppen:
   * **Säkra förslag**: samma namn (skiftläge, accenter och bindestreck ignoreras, å/ä/ö behålls) hos exakt en person på båda sidor. Förvalda.
   * **Ändrade uppgifter**: samma laget.se-ID men nytt namn eller ny roll. Förvalda.
   * **Välj själv**: samma namn flera gånger, eller bara liknande namn (för- och efternamn, eller samma efternamn och initial). Aldrig förvalda.
   * **Ingen träff** åt båda hållen, och befintliga kopplingar som saknas i filen. De visas men ändras inte.
4. Administratören bockar av och sparar. Samma laget.se-person kan inte väljas för två personer.

Namn används bara för att föreslå kopplingar. Exporten matchar alltid på ID.

## Direktsynk via synkagenten

Exportvyn har **Skicka till laget.se**, som ett alternativ till att skapa en fil. Synken kräver att lagets namn i
laget.se-adressen är ifyllt under Integrationer. Medlemsimporten fyller i det automatiskt.

1. Appen lägger underlaget (samma JSON-kontrakt som filen) i `attendance_export.sync_jobs`
   (`api.attendance_export_request_sync`). Servern kontrollerar samma regler som för filen, och dessutom att varje
   person finns som koppling i laget.
2. Synkagenten (`C:\Dev\laget-playwright`, `laget-synk.cmd`) körs på administratörens dator, som
   den inloggade Teamzone-användaren. Den hämtar jobbet, läser aktiviteten i laget.se och rapporterar en
   förhandsgranskning (`awaiting_approval`).
3. Administratören ser ändringarna i appen och godkänner exakt den förhandsgranskningen
   (`approve_sync` med förhandsgranskningens SHA-256).
4. Agenten läser sidan igen. Om något har ändrats krävs ett nytt godkännande. Annars genomförs och
   verifieras ändringarna. Resultatet blir `verified`, som också loggas som en `verified`-post i
   `attendance_export.exports`, eller `failed` med orsak.

Underlaget (`payload`) töms när jobbet avslutas. Teamzone lagrar fortfarande inga laget.se-uppgifter.
Exportvyn visar om agenten är igång (hjärtslag i `attendance_export.agents`) och om den behöver logga in på
laget.se igen.

**Automatisk sökning av aktiviteten** (migration `20261015090000_attendance_export_locate_activity.sql`): saknas
aktivitetskoppling skickas synken ändå, med `activityId: ''`. Agenten letar då i lagets kalender
(`/<lag>/Calendar`, månads- och årsval, `tr.listEventsRow`) efter samma datum och starttid i lagets tidszon.

* **Exakt en träff:** kopplingen sparas (`agent_report_located`) och jobbet fortsätter till förhandsgranskningen.
* **Flera träffar samma tid:** typen avgör (träning, match eller övrigt).
* **Ingen träff på tiden:** finns exakt en träning (eller match) samma dag kopplas den ändå. Tiderna kan
  skilja sig mellan systemen, t.ex. 17:30 och 18:00. Gäller inte "övrigt".
* **Annars:** `needs_activity` med dagens aktiviteter som förslag. I appen väljer administratören en
  aktivitet, och synken skickas om.

Om månadsbytet inte går med skrivspärren på avbryter agenten och ber om länken. En fil kräver alltid en
aktivitetskoppling. Att skapa aktiviteter i laget.se är inte byggt.

## Statusöversättning

| Teamzone (`core.attendance_facts.status`) | Fil |
| --- | --- |
| `present`, `late`, `partial` | `present: true` (samma som Teamzones närvarostatistik) |
| `absent` | `present: false` |
| `unknown` / ingen registrering | **tas inte med**, och en varning visas |

Kallelsesvar (kallad, tackat ja/nej, inte svarat) används aldrig.

## Vem som ingår

* Underlaget omfattar personer med registrerad närvaro eller aktiv kallelse till aktiviteten.
* Medlemmar i laget (spelar- eller ledaruppdrag vid aktivitetens tid) ingår när de har uttrycklig status.
* Gäster utan uppdrag i aktivitetens lag måste kopplas, eller uttryckligen väljas bort i exportvyn.
* Medlemmar i andra lag som delar aktiviteten ingår bara om de har en koppling i det exporterade laget. Annars påverkas de inte.

## Exportregler och validering

Exporten stoppas, och ingen fil skapas, om något av följande gäller:

* Integrationen är avstängd.
* Aktiviteten tillhör inte laget, är inte avslutad (sluttiden har inte passerat) eller är inställd.
* Laget.se-ID saknas eller är ogiltigt, eller aktivitetskopplingen tillhör ett annat lag.
* Någon som ingår saknar koppling, t.ex. "Kan inte exportera: 2 spelare saknar laget.se-ID."
* Ett externt ID är ogiltigt, namn saknas eller rollen är ogiltig.
* Samma laget.se-ID är kopplat till flera personer, en person har flera kopplingar, eller en koppling tillhör ett annat lag.
* Okänd närvaro har hamnat i filen (defensiv kontroll).
* Administratören har inte bekräftat att närvaron är färdigregistrerad.

**Färdigställd närvaro.** Teamzone har ingen sådan status. Den minimala
lösningen är att administratören bekräftar att underlaget är komplett i
exportvyn. Bekräftelsen sparas på exportposten
(`attendance_export.exports.confirmed_complete`). Närvaromodellen och
aktivitetshanteringen påverkas inte.

Valideringen i Teamzone ersätter inte prototypens kontroll mot laget.se.

## Exportstatus

Exportloggen (`attendance_export.exports`) innehåller bara antal och en
SHA-256 av filen, aldrig namn eller själva filen.

* Ingen post betyder **Inte exporterad**.
* `file_created` betyder **Exportfil skapad**. Det betyder *inte* att aktiviteten är synkroniserad.
* `failed` betyder **Export misslyckades** (filen kunde inte sparas).
* `verified` och `rejected`, plus `verified_at` och `verification_note`, är reserverade för framtida återrapportering från synkverktyget. De är inte implementerade.

Upprepad export av samma aktivitet är tillåten. Ett oförändrat underlag ger
en identisk fil (deterministisk ordning) och visas som "oförändrat sedan …".

## Behörighet

* Inställningar och medlemskopplingar kräver `team.roster.manage` i laget.
* Aktivitetskoppling och export kräver aktivitetens närvarobehörighet
  (`internal.actor_can_manage_attendance`), och aktiviteten måste höra till laget.

Servern kontrollerar reglerna den kan se en gång till när exporten loggas.

## Förberett, inte implementerat

* Markering av importerade kopplingar: `member_links.source = 'import'` finns, men importen sparar i dag via samma RPC som manuella kopplingar (`manual`), så att ingen ny SQL behövs.
* Flera mottagare: `provider` finns i alla tabeller.
* Batchexport: tjänsterna tar ett aktivitets-ID åt gången och kan anropas i loop.
* Verifierad synkronisering: se Exportstatus.

## Funktionsflagga

`--dart-define=TEAMZONE_ATTENDANCE_EXPORT=false` döljer alla ingångar utan
att ta bort kod. Standardvärdet är `true`.

## Borttagning

1. Ta bort krokarna. Alla är markerade med `attendance-export:hook`:
   ```bash
   git grep -n "attendance-export:hook"
   ```
   * `lib/src/app/teamzone_app.dart`: importen.
   * `lib/src/core/supabase/supabase_bootstrap.dart`: importen och `AttendanceExportFeature.configure(...)`.
   * `lib/src/features/calendar/event_details_page.dart`: menyposten "Exportera närvaro → laget.se".
   * `lib/src/features/account/profile_settings_surface.dart`: `...AttendanceExportFeature.teamSettingsEntries(...)`.
2. Radera `lib/src/features/attendance_export/` och `test/attendance_export_*_test.dart`.
   I synkverktyget kan `src/members.ts` och kommandot `members` tas bort.
3. Ta bort `crypto` ur `pubspec.yaml` om inget annat använder det.
4. Kör `supabase/removal/attendance_export_remove.sql`. Skriptet tar bort
   `api.attendance_export_*` och schemat `attendance_export` (cascade). Inga
   kärntabeller påverkas.
5. Radera det här dokumentet och borttagningsskriptet.
