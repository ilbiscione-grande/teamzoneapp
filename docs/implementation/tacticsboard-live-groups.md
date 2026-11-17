# Tacticsboard: grupparbete i livelektionen – plan

**Status: steg 1–3 byggda 2026-11-17 och testade i webbläsaren mot testdatabasen. Steg 1–2 är i produktion, och deras migreringar är körda där och deployade till webtools.teamzoneapp.se. Steg 3 (`20270403090000_tactics_live_group_extras`) är bara kört i testdatabasen. Steg 4 återstår.**

Under en livelektion delar läraren in deltagarna i grupper. Varje grupp får en egen kopia av tavlan och ändrar den tillsammans, som en sandlåda. När läraren tar ordet igen går alla tillbaka till lärarens vy och sandlådorna kastas. Det passar särskilt ledarutbildningar, som är det långsiktiga målet med livelektionerna.

## Det som redan finns

- **Livelektionen** (`webtools/lib/tactics/live.ts`, `webtools/components/tactics/live/`, migreringarna `*_tactics_live*.sql`):
  - Privata Realtime-kanaler, `tactics-live:<id>` och `tactics-live-host:<id>`.
  - Bara läraren sänder direkt. Allt en deltagare skickar går via RPC:er och `realtime.send`.
- **Ge ordet** (`use-floor.ts`, `move_tactics_live_floor`). Den som har ordet flyttar objekt på lärarens tavla:
  - Medan objektet dras skickas bara rörelsen (`dropped = false`).
  - När objektet släpps blir läget kvar.
  - Skickandet är redan bromsat (`throttle`).
- **Ritning** (`live-draw.ts`, `tactics_live_strokes`) med lägena av, egna anteckningar och gemensamt. Varje deltagare har sin egen färg.
- **Platser i lektionen** (`tactics_live_participants`, platsbegränsningen i `*_tactics_live_seats.sql`).
- **Slut efter 30 minuter utan aktivitet** (`*_tactics_live_idle.sql`).

Grupparbete är i grunden *ge ordet* flera gånger samtidigt. Skillnaden är att varje grupp har en egen kopia av tavlan och en egen kanal.

## Flödet

1. **Läraren startar grupparbete.** Läraren väljer:
   - antal grupper,
   - om deltagarna fördelas automatiskt eller för hand (dra en deltagare till en grupp),
   - vilken tavla och frame grupperna utgår från (som standard den som visas nu),
   - eventuellt en tid, till exempel 5 minuter, med nedräkning hos alla.
2. **Deltagarna arbetar i sin grupp.** Varje deltagare ser bara sin egen grupps kopia och vilka som är med i gruppen. Lärarens projekt rörs inte.
3. **Läraren ser alla grupper.** En översikt visar en liten bild av varje grupps tavla, som uppdateras live. Läraren kan:
   - gå in i en grupp för att följa den eller hjälpa till,
   - flytta en deltagare till en annan grupp.
4. **Grupperna redovisar.** Med *Visa grupp för alla* ser hela klassen en grupps kopia, en grupp i taget. Läraren kan jämföra grupperna efter varandra.
5. **Läraren tar ordet igen.** *Avsluta grupparbete* tar alla tillbaka till lärarens vy och raderar kopiorna. Innan dess kan läraren spara en grupps lösning som en ny tavla i projektet.

## Teknisk uppbyggnad

### Databas

- **Ny tabell `core.tactics_live_groups`:**
  - `id`, `session_id`, `number`, `name`,
  - `board jsonb`, gruppens kopia av tavlan,
  - `version integer`, som räknas upp vid varje sparat läge,
  - `created_at`, `updated_at`.
- **`core.tactics_live_participants` får `group_id`.** Den är null utanför grupparbete.
- **`core.tactics_live_sessions` får `groups_active boolean`** och eventuellt `groups_ends_at`, för nedräkningen.
- **Ritning i grupperna:** `tactics_live_strokes` får `group_id`. Linjer i en grupp raderas med gruppen.
- Raderingen kaskaderar från sessionen. Både när lektionen avslutas och när den stängs efter 30 minuter utan aktivitet försvinner grupperna. Grupparbete räknas som aktivitet.

### RPC:er (mönstret `internal.*_for_actor` + `api.*`)

- **Läraren:**
  - `start_tactics_live_groups(session, group_count, board_id, frame_index, assignment jsonb | null, minutes | null)` skapar grupperna, kopierar tavlan, fördelar deltagarna och sänder `groups-started` på lektionens kanal.
  - `assign_tactics_live_group(session, profile, group)` flyttar en deltagare.
  - `show_tactics_live_group(session, group | null)` visar en grupp för alla, eller ingen.
  - `end_tactics_live_groups(session, keep_group | null)` raderar grupperna och sänder `groups-ended`. Att spara en lösning görs på klientsidan genom att lärarens editor lägger in gruppens tavla som en ny tavla. Därför räcker det att RPC:n returnerar tavlan för `keep_group` innan raderingen.
- **Deltagaren:**
  - `move_tactics_live_group(session, board_id, frame_index, moves, dropped)` är samma sak som `move_tactics_live_floor`, men kontrollerar gruppmedlemskapet i stället för ordet och sänder på gruppens kanal. När `dropped = true` skrivs läget in i `board` och `version` räknas upp.
  - `get_tactics_live_group(session)` hämtar den egna gruppens tavla, version och medlemmar. Den används vid omladdning och sen anslutning.

### Realtime

- **En kanal per grupp:** `tactics-live-group:<session>:<grupp>`. Den är privat. Policyn på `realtime.messages` släpper in gruppens medlemmar och lektionens lärare.
- **Läraren lyssnar på alla grupper,** och det är det som driver översikten. Med några grupper är det ett fåtal kanaler och inga problem.
- **Lektionens kanal** får nya händelser: `groups-started`, `group-assigned`, `group-shown` och `groups-ended`. Klienten byter vy på dessa.
- **Krockar:** om två personer flyttar samma objekt gäller den senaste flytten. `version` gör att en klient som tappat meddelanden märker det och hämtar tavlan på nytt.

### Klient (`webtools/components/tactics/live/`)

- `GroupSetup.tsx`: lärarens dialog för antal grupper, fördelning och tid.
- `GroupOverview.tsx`: lärarens rutnät med en liten bild per grupp, plus *Gå in*, *Visa för alla* och *Avsluta*.
- `use-live-group.ts`: deltagarens gruppkanal och flytt av objekt. Den återanvänder dragandet från `use-floor.ts`.
- `group-store.ts`: gruppens tavla och version.
- `LiveViewer.tsx` visar gruppens kopia i stället för lärarens tavla när deltagaren är i en grupp.
- Rena funktioner för fördelning och sammanslagning av rörelser hamnar i `webtools/lib/tactics/live-groups.ts` med tester i `webtools/tests/`.
- Texterna läggs i `webtools/lib/i18n/` både på svenska och engelska.

### Belastning

Typiskt är det 3–6 grupper med 2–4 personer var. Rörelser bromsas som i dag, och bara släppta lägen skrivs till databasen. Det ryms med god marginal i Realtime-kvoten. Tavlans JSON är liten jämfört med gränsen för storleken på ett meddelande.

## Steg

1. **Grupper och kopior.** Det här steget innehåller:
   - tabellen, kolumnerna och RPC:erna för att starta, flytta objekt, hämta och avsluta,
   - gruppkanalen med sin policy,
   - lärarens dialog och *Avsluta grupparbete*,
   - deltagarens vy av gruppens kopia där alla i gruppen kan flytta objekt.

   Sandlådan kastas när grupparbetet avslutas.
2. **Lärarens översikt.** Rutnätet med grupperna, *Gå in i grupp*, *Visa grupp för alla* och att flytta deltagare mellan grupper.

   Så blev det byggt:
   - Översikten visar en liten bild per grupp som uppdateras live. Läraren lyssnar på alla gruppkanaler.
   - *Gå in i grupp* blev *Följ*: gruppens kopia stor, med nummer, medlemmar och *Visa för alla*. Läraren kan bara titta där, inte flytta. Lärarens tavla är projektet och sparas automatiskt, så den kan inte bära en grupps kopia. Att hjälpa till i en grupp kräver en egen tavla för läraren, utanför projektet, och hör till steg 3 eller 4.
   - *Visa för alla* sparas i `tactics_live_sessions.shown_group`. Den visade gruppens flyttar går även ut på lektionens kanal som `shown-move`. Den visade gruppen fortsätter arbeta, och de andra tittar. När läraren slutar visa kommer alla tillbaka till sin egen grupp.
   - Att flytta en deltagare sänder `group-assigned`. Deltagaren byter då kopia och kanal direkt.
3. **Mer i grupperna.** Ritning och chatt inom gruppen, nedräkning och *Spara som ny tavla*.

   Så blev det byggt:
   - Streck och meddelanden får `group_id` och raderas med gruppen. Klassens ritlager och chatt hämtar och rensar bara sina egna rader.
   - Gruppen ritar alltid på sin kopia, oavsett klassens ritläge. Gruppchatten stoppas bara om läraren har stängt av chatten för deltagaren. Läraren läser gruppens chatt i *Följ*.
   - Nedräkningen ligger i `tactics_live_sessions.groups_ends_at`. Läraren väljer 2–15 minuter eller ingen tid. Inget händer automatiskt när tiden är ute; läraren avgör när grupperna är klara.
   - *Spara som ny tavla* görs i lärarens editor från kopian läraren redan har. Tavlan läggs sist i projektet, och gruppens streck blir frihandslinjer på gruppens frame. Läraren stannar på tavlan som visas.
   - Läraren kan fortfarande inte flytta objekt i en grupps kopia. Det kräver en egen tavla för läraren, utanför projektet. Det hör ihop med steg 4.
4. **Senare, om det behövs:** full redigering i grupperna, alltså att lägga till och ta bort spelare, pilar och zoner. Det kräver en enklare redigerare för deltagarna och att ändringarna skickas som ändringar av tavlan, inte bara som rörelser. Det är det största steget och tas bara om flytt och ritning inte räcker.

## Öppna frågor

- **Får grupperna bara flytta objekt och rita (förslaget), eller även redigera fullt ut?** Se steg 4.
- **Får alla i gruppen ändra samtidigt (förslaget), eller en i taget med ordet inom gruppen?**
- **Får gäster vara med i grupper?** Förslaget är ja, på samma villkor som i lektionen i övrigt.
- **Ska gruppernas lösningar ingå i sammanfattningen efter lektionen** (`LiveSummary.tsx`)? Då måste de sparas och inte bara kastas.
- **Ska grupparbetet följa med när lektioner kan spelas in?** Det är önskat senare. Händelserna ovan går att spela upp igen, så det stänger inte den dörren.
