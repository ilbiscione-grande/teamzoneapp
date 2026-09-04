# Hosted migrationsbacklog stängd (2026-09-04)

## Bakgrund

Efter att veckans arbete säkrades i git (`c0454e4`, `6ffcc7c`, `4de45c9`) och
REL-01 bekräftades grön lokalt, återupptogs det pausade audit-Supabase-
projektet `TeamzoneApp` (`hgcshgunvooyudvrcpig`, region `eu-west-1`) på
produktägarens begäran. `supabase migration list` visade två separata problem
mot hosted, inga liveändringar gjordes förrän båda var förstådda.

## 1. Bokföringsdrift (fem migrationer)

Fem lokala migrationsfiler var omdöpta efter att deras SQL redan applicerats
mot hosted under ett annat versionsstämpel. Bekräftat genom en read-only
`select version,name from supabase_migrations.schema_migrations` — namnen
matchade exakt de aktuella lokala filerna:

| Lokal fil | Applicerad som (innan reparation) |
|---|---|
| `20260902115000_cal10_restore_callup_response_context_dependency.sql` | `20260902114411` |
| `20260902120500_cal10_restore_callup_reminder_columns.sql` | `20260902114644` |
| `20260902133929_auth03_targeted_player_claim_creates_context.sql` | `20260902134106` |
| `20260902215140_team05_fix_renamed_guardian_claim_parameter.sql` | `20260902215304` |
| `20260903082224_auth03_fix_renamed_invitation_claim_parameter.sql` | `20260903082358` |

Löst med `supabase migration repair` (bokföring endast, ingen SQL kördes om):
de fem gamla versionsraderna markerades `reverted`, de fem aktuella lokala
versionerna markerades `applied`.

## 2. Genuint väntande migrationer (47 filer)

Efter reparationen visade `supabase migration list` 47 lokala migrationer utan
motsvarande hosted-post — allt från `cal02` (2026-08-27) till `auth04_fix_...`
(2026-09-03). Det här matchar exakt de återkommande noteringarna
"SQL-runtime återstår" i `core_app_delivery_cards.md` för i princip hela
CAL/PUB/MSG/HOME/AC-backloggen.

Ett `supabase db push --linked --dry-run --include-all` visade en ren,
förväntad plan utan överraskningar. Den riktiga pushen kördes därefter
iterativt: varje fil körs i sin egen transaktion, så ett fel rullar tillbaka
just den filen utan att skada tidigare applicerade migrationer eller lämna
delvis tillstånd (verifierat explicit efter första felet).

### Verkliga fel som pushen hittade och som lokal Dart-strängmatchning aldrig kunnat upptäcka

Eftersom miljön saknar lokal Docker/Postgres har dessa migrationers SQL
aldrig körts mot en riktig databas förrän nu — bara kontrollerats som text i
Flutter-testerna. Pushen fungerade därför som en riktig syntax-/semantik-
verifiering och hittade:

1. **`cal02_event_editor_locations.sql`** – en obalanserad parentes i
   `internal.revise_event_v2_for_actor` (`jsonb_build_object(...)`-anropet
   saknade sin avslutande parentes). Genuint syntaxfel, skulle aldrig ha
   kunnat deployas.
2. **`cal03_shared_event_access.sql`** – en obalanserad parentes i
   `internal.update_event_sharing_for_actor`s `if exists(...)`-villkor
   (samma klass av fel, en parentes för lite).
3. **`msg08_notification_center.sql`** – `internal.notification_deep_link`
   byggde deep links som `'/inbox?thread='||outbox.payload_ref->>'thread_id'`.
   `||` och `->>` har samma precedens i Postgres och utvärderas vänster-till-
   höger, så uttrycket tolkades som
   `('/inbox?thread='||outbox.payload_ref)->>'thread_id'` — Postgres försökte
   då tolka strängliteralen som jsonb och kraschade med
   `invalid input syntax for type json`. Fixat med explicit parentes runt
   `->>`-uttrycket. Hela migrationsmappen genomsöktes efter samma mönster;
   inga fler träffar.
4–6. **Idempotens mot redan applicerat tillstånd** i `cal04`, `cal06`, `cal07`,
   `cal08` samt fem funktioner i `cal07/cal08/msg02/msg06/msg08`: enskilda
   kolumner, ett constraint, ett index och fem funktionsdefinitioner fanns
   redan i hosted (troligen från tidigare ad-hoc-verifieringsscript som
   kördes direkt mot databasen under utveckling, inte via `db push`). Varje
   träff kontrollerades read-only mot `information_schema`/`pg_constraint`/
   `pg_indexes`/`pg_proc` innan ändring, för att bekräfta att formen redan
   matchade exakt (samma typ, samma default, samma villkor) innan filen
   gjordes idempotent (`add column if not exists`, `create index if not
   exists`, ett `do $$ ... if not exists(select 1 from pg_constraint ...)`-
   block för constraints, `create or replace function` för de fem
   funktionerna). Ingen data eller tidigare applicerad form ändrades.

Nio migrationsfiler ändrades totalt: `cal02`, `cal03`, `cal04`, `cal06`,
`cal07`, `cal08`, `msg02`, `msg06`, `msg08`.

## Resultat

- `supabase migration list`: **0 kvarvarande diff** — samtliga 161 lokala
  migrationer är nu applicerade på hosted, exakt matchande versionsstämplar.
- `supabase db advisors --type security`: endast den redan kända, dokumenterade
  `auth_leaked_password_protection`-varningen (kräver Pro-plan, se
  `docs/security/s01_auth_policy.md`). Inga nya säkerhetsfynd.
- `supabase db advisors --type performance`: två `auth_rls_initplan`-varningar
  på `realtime.messages`-policyerna `teamzone_inbox_broadcast_select` och
  `teamzone_notification_center_broadcast_select` (från MSG-01/MSG-08) —
  `auth.<function>()` bör wrappas som `(select auth.<function>())` i RLS-
  villkoret för bättre skalprestanda. Inte en korrekthets- eller
  säkerhetsbrist; **kvarstår som ett separat, litet performance-uppföljningsjobb.**

## Gräns

Endast migrationer pushades. Ingen data skrevs, inga Edge Functions
deployades, ingen produktionsprovisionering och ingen ändring av
`Teamzone6`. Reparation och push kördes uteslutande mot det länkade
greenfield-projektet `hgcshgunvooyudvrcpig`.

## Uppföljning 2026-09-05 – performance-varningen stängd

De två `auth_rls_initplan`-varningarna löstes med en ny migration,
`20260905000151_perf_wrap_auth_uid_in_realtime_broadcast_policies.sql`, som
tar om de två policyerna på `realtime.messages`
(`teamzone_inbox_broadcast_select`, `teamzone_notification_center_broadcast_select`)
med `auth.uid()` wrappat som `(select auth.uid())`, konsekvent med hur
`realtime.topic()` redan var skrivet i samma villkor. Ingen ändring av
predikatets logik eller åtkomstresultat — bara evalueringsfrekvens per rad
kontra per statement.

`supabase migration list` visar 162/162 synkade efter pushen. Ett omkört
`supabase db advisors --type performance` gav **"No issues found"**.

## Konsekvens för delivery cards

Detta stänger SQL-runtime-delen av den återstående grinden för CAL-02, CAL-03,
CAL-04, CAL-06, CAL-07, CAL-08, PUB-02–PUB-06, MSG-01–MSG-08, HOME-01–HOME-05
och AC-01/AC-03–AC-08. Fysisk/hosted enhets- och flerrollsverifiering är
fortsatt en separat, inte genomförd grind för dessa kort; `core_app_delivery_
cards.md`s individuella statusrader är ännu inte uppdaterade fil-för-fil och
bör synkas i ett uppföljande steg.
