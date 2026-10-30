# Tacticsboard: versioner, ledarnas rättigheter och tavlor i träningar och matcher – plan

**Status 2026-10-30:**
- Steg 1 är byggt: `supabase/migrations/20270101090000_tactics_versions.sql`, testat i `supabase/tests/tactics_versions.local.mjs`.
- Steg 2 är byggt: `20270102090000_tactics_leader_access.sql`, testat i `supabase/tests/tactics_leader_access.local.mjs`. En ledare som bara får titta ser projektet i samma vy som en delad länk, med knappen "Gör en kopia".
- Steg 3 är byggt: `20270103090000_tactics_player_links.sql`, testat i `supabase/tests/tactics_player_links.local.mjs`.
  - `internal.issue_tactics_player_link(projekt, tavla)` ger den inloggade en egen länk som gäller i 6 timmar.
  - Ingen kan anropa funktionen direkt. Steg 4:s funktioner anropar den efter sina egna kontroller.
- Steg 4 är byggt: `20270104090000_tactics_event_boards.sql`, testat i `supabase/tests/tactics_event_boards.local.mjs`.
  - Matchplanen har kortet "Tavlor" (`match_plan_links.dart`) och tavlorna visas i spelarnas sammanfattning.
  - Träningen har SQL:en `api.open_training_block_board`. Knappen "Visa tavla" i appen väntar på träningssessionen, som har pågående ändringar i de filerna.
  - Tavlor från klubbens eller TeamZones bibliotek (`club`, `teamzone`) visas inte för spelarna än (`library_board`).
- Steg 5 är planerat. Produktägaren vill koppla Tacticsboard till TeamZones träningar och matcher. Spelarna ska se tavlorna och andra ledare ska kunna arbeta med dem, men utan att någon kan förstöra originalet. Steg 1 (versioner) är användbart på egen hand och byggs först.

## Beslut som styr planen

- **Spelarna ser den delade vyn**, alltså samma visning som en delad länk (`SharedViewer`): spela upp, svepa och välja "Jag är…". De ser aldrig editorn.
- **Bara lagets spelare kommer åt tavlan.** En vanlig delad länk fungerar för alla som har den. Appen ber därför om en kort länk som gäller i några timmar och som bara delas ut till den som är med i laget.
- **Ledarna arbetar i originalet**, inte i kopior. Spelarna ser den senast sparade versionen, så det finns bara en tavla att hålla rätt.
- **Originalet skyddas på två sätt:**
  - Skaparen bestämmer per projekt om lagets andra ledare får *titta* (förvalt) eller *redigera*.
  - Varje projekt har en versionshistorik som skaparen kan gå tillbaka i.
- **"Gör en kopia"** finns för den ledare som vill göra en egen variant. Kopian kopplas inte till aktiviteten.
- **Modulgränserna gäller:** tavlor för en match hör till matchmodulen (matchplanen) och tavlor för en träning hör till träningsmodulen. Aktivitetssidan förblir enkel.

## Det som redan finns

- **Projekten** (`core.tactics_projects`, `supabase/migrations/20261123090000_tacticsboard.sql`):
  - De har en ägare (`owner_id`), ett lag (`teamzone_team_id`) och ett `revision`-nummer.
  - `internal.save_tactics_project_for_actor` skriver hela dokumentet och nekar en sparning som utgår från en äldre revision (`stale_revision`).
  - Bara ägaren får spara.
  - Den gamla versionen skrivs över, så det finns ingen historik.
- **Lagets ledare** fås från `internal.tournament_actor_teams()`. Funktionen ger de aktiva lag där den inloggade har rollen `leader` och rättigheten `event.manage`.
- **Delade länkar** (`core.tactics_share_links`, `api.get_shared_tactics`):
  - En länk är en token som gäller tills ägaren återkallar den (`revoked_at`). Länkarna har inget utgångsdatum.
  - En länk gäller hela projektet eller en enda tavla (`board_id`).
- **Matchplanens bilagor** (`core.module_attachments`, `20261203090000_match_plans.sql`):
  - Idag finns bara `kind = 'link'`. Kommentaren i migrationen säger redan "Tacticsboard boards later".
  - Varje bilaga har `visible_to_players`. Planen visas för spelarna när den är publicerad (`published`).
- **Träningsövningar** (`core.training_blocks`, `20261222090000_training_block_boards.sql`):
  - En övning kan ha en tavla kopplad (`board_source`, `board_ref`, `board_id`).
  - Källan är `mine` (ett projekt i `core.tactics_projects`), `club` eller `teamzone` (bibliotek).
  - Spelarna kan inte öppna tavlan idag.

## Steg 1: Versionshistorik

**Databas** (`20270101090000_tactics_versions.sql`). Versionerna tas av en trigger på `core.tactics_projects`, så varje skrivning täcks, även när träningens pass sparas tillbaka:

```sql
create table core.tactics_project_versions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references core.tactics_projects(id) on delete cascade,
  revision bigint not null,              -- projektets revision när versionen sparades
  name text not null,
  document jsonb not null,
  saved_by uuid references core.profiles(id) on delete set null,
  saved_at timestamptz not null,         -- när det gamla innehållet senast sparades
  reason text not null check (reason in ('edit', 'other_editor', 'before_restore')),
  created_at timestamptz not null default now()
);
create index tactics_project_versions_project on core.tactics_project_versions (project_id, saved_at desc);
alter table core.tactics_projects add column last_saved_by uuid references core.profiles(id) on delete set null;
```

**När en version sparas.** Det sker i sparfunktionen, innan det gamla dokumentet skrivs över. En version per autosparning skulle bli hundratals, så en ny version tas bara när något av följande gäller:

- den senaste versionen är äldre än 30 minuter (`edit`)
- en annan person sparar än den som sparade sist (`other_editor`), vilket blir aktuellt först i steg 2
- någon återställer en version: det nuvarande innehållet sparas först (`before_restore`), så återställningen går att ångra

Hela dokumentet sparas i varje version. Tavlorna är små JSON-dokument och behöver inga diffar.

**Rensning.** De 10 senaste versionerna sparas alltid. Äldre versioner tas bort när de är mer än 90 dagar gamla. Rensningen sker i samma sparning, så inget schemalagt jobb behövs.

**RPC:er** (bara ägaren i steg 1):
- `api.list_tactics_versions(target_project_id)`: id, tid, vem som sparade, namn, antal tavlor och orsak.
- `api.get_tactics_version(target_version_id)`: dokumentet, för att förhandsvisa.
- `api.restore_tactics_version(target_version_id, expected_revision)`:
  - sparar det nuvarande innehållet som `before_restore`
  - skriver in versionen och ökar revisionen
  - nekar med `stale_revision` om projektet har ändrats under tiden, precis som en vanlig sparning

**Gränssnitt i webtools:**
- "Versioner…" i projektmenyn öppnar en lista som "Tors 19:40 · Anna · 4 tavlor".
- Ett val öppnar versionen skrivskyddad, med samma visning som en delad länk (`BoardStage` med `editable={false}`).
- Knappen "Återställ den här versionen" frågar först och laddar sedan om projektet.
- "Gör en kopia av versionen" skapar ett nytt projekt, för den som bara vill hämta en enskild tavla.

**Tester:**
- SQL-texttester enligt mönstret i `webtools/tests/tactics-folder-share.test.ts`, för behörigheter och för att `grant`/`revoke` finns.
- Enhetstest för regeln om när en version sparas, om den läggs i en ren funktion.

## Steg 2: Ledarnas rättigheter per projekt

**Databas:**
- Ny kolumn: `alter table core.tactics_projects add column leader_access text not null default 'view' check (leader_access in ('view', 'edit'))`.
- Kolumnen gäller bara när projektet har ett lag (`teamzone_team_id`).
- En ledare är den som har projektets lag i `internal.tournament_actor_teams()`.

**Vem får göra vad:**

| | Ägaren | Ledare (titta) | Ledare (redigera) | Övriga |
|---|---|---|---|---|
| Öppna i editorn, skrivskyddat | ✓ | ✓ | ✓ | – |
| Spara ändringar | ✓ | – | ✓ | – |
| Gör en kopia | ✓ | ✓ | ✓ | – |
| Byta namn, lag eller rättigheter, ta bort, dela, versioner | ✓ | – | – | – |
| Se versioner | ✓ | – | ✓ (bara se) | – |

- `api.list_tactics_projects` får lagets projekt i en egen grupp, "Lagets tavlor". Varje projekt får fältet `access`, som är `owner`, `edit` eller `view`.
- Sparfunktionen tillåter ägaren, och en ledare när `leader_access = 'edit'`.
- När en annan person sparar tas alltid en version (`other_editor`, se steg 1).
- Om två sparar samtidigt nekas den senare med `stale_revision`, som idag. Editorn behöver då en tydlig ruta: "Tavlan har ändrats av Anna. Ladda om (dina senaste ändringar sparas som en kopia)". Idag hanteras det felet bara för en och samma person i två flikar.
- I editorn ser en ledare som bara får titta tavlan i läsläge, med knappen "Gör en kopia".

**Rättigheter i gränssnittet:** "Lagets ledare kan: titta / redigera" under projektets inställningar. Det syns bara för ägaren och bara när projektet har ett lag.

Steg 2 hör ihop med behörighetsgenomgången (`docs/implementation/permissions-review.md`). Rollerna här ska stämma med den.

## Steg 3: Läsrätt för lagets spelare (korta länkar)

**Databas:**
- `alter table core.tactics_share_links add column expires_at timestamptz, add column issued_to uuid references core.profiles(id) on delete cascade`.
- `api.get_shared_tactics` och mappens motsvarighet godtar inte en token vars `expires_at` har passerat. Dagens länkar har inget `expires_at` och fungerar som förut.
- Ny RPC för appen: `api.open_event_tactics(target_attachment_id)` för matchplanen. Träningen behöver en motsvarande RPC.
  - Kontrollerar att den inloggade är med i lagets trupp för aktiviteten. Samma kontroll som när spelaren läser aktiviteten och matchplanen ska återanvändas, inte skrivas om.
  - Kontrollerar att bilagan visas för spelarna och att planen är publicerad.
  - Återanvänder en giltig kort token för samma person och tavla, och skapar annars en ny som gäller i 6 timmar.
  - Returnerar adressen till den delade sidan.
- Utgångna korta länkar rensas när nya skapas.

**I appen:** knappen öppnar adressen i webbläsaren eller i appens webbvy. Spelaren behöver inte logga in i webtools, och den som får en vidarebefordrad länk kan bara använda den i några timmar.

**Öppen fråga:** övningar vars tavla kommer från biblioteket (`club`, `teamzone`) och inte från ett projekt. Antingen visas biblioteksobjektets tavla på samma sätt, med en egen läsfunktion, eller så kopieras tavlan in i lagets projekt när den kopplas. Det andra är enklare och gör att lagets ledare kan anpassa den.

## Steg 4: Kopplingen i matchplanen och träningen

Det här steget rör matchmodulen och träningsmodulen. Det ska stämmas av med sessionen som arbetar där innan det byggs.

**Matchplanen:**
- `core.module_attachments` får `kind = 'tactics'`, med `project_id` och ett valfritt `board_id` (null betyder hela projektet).
- Ledaren väljer under "Tavlor" i matchplanen bland lagets projekt och sina egna.
- Bilagan har samma val för spelarvisning som länkarna, och visas när planen publiceras.
- Spelaren ser "Tavlor" i den publicerade matchplanen, och ett tryck öppnar en kort länk (steg 3).

**Träningen:**
- Övningar som redan har en tavla får "Visa tavla" för spelarna.
- Tavlorna följer samma synlighet som övningen eller passet har för spelarna.

**I Tacticsboard (senare):** "Koppla till…" i projektmenyn listar lagets kommande matcher och träningar. Det är ett alternativ till att välja tavlan från appen.

## Steg 5 (senare, vid behov): Förslag

En ledare som bara får titta gör ändringar i en kopia och skickar den som förslag. Ägaren ser förslaget och väljer *Använd* (ersätter tavlan, med en version före) eller *Avböj*, per tavla. Steget byggs först när steg 1–2 inte räcker.

## Leverans

- SQL lämnas till produktägaren som kör den, tillsammans med en rad för `schema_migrations`. Steg 1, 2 och 3 är var sin migration.
- Varje steg är en egen commit, och webtools driftsätts efter steg 1, 2 och 3.
- Varje steg avslutas med:
  - tester i `webtools/tests`
  - `npx tsc --noEmit`
  - kontroll i webbläsaren i mobil- och datorbredd

## Uppskattning

| Steg | Omfattning |
|---|---|
| 1. Versioner | 1 migration, 3 RPC:er, versionslista och förhandsvisning i webtools |
| 2. Ledarnas rättigheter | ändrade RPC:er för lista och sparning, läsläge och konfliktruta i editorn |
| 3. Korta länkar | 2 kolumner, 1–2 RPC:er, kontroll av utgångstid i läsfunktionerna |
| 4. Matchplan och träning | ny bilagetyp, val och visning i två moduler (Flutter) |
