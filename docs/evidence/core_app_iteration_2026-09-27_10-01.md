# Grundappens utbyggnad 2026-09-27 – 2026-10-01

**Status:** levererat till testprojektet `hgcshgunvooyudvrcpig`. App och publik sajt driftsatta; en migration väntar (se nedan).
**Commits:** `d4bad8b` … `fe333da` på `main`.
**Leveranskort:** TEAM-09–TEAM-12, CAL-12–CAL-14, MSG-09, PROF-01–PROF-05, AUTH-08, PUB-10–PUB-13 och SET-01 i
[`core_app_delivery_cards.md`](../implementation/core_app_delivery_cards.md).

Den här filen samlar perioden efter dokumentationssynken 2026-09-26 (`151da6e`). Detaljerade
funktionsbeskrivningar finns i [`team-leader-permissions.md`](../implementation/team-leader-permissions.md),
[`team-person-functions-positions.md`](../implementation/team-person-functions-positions.md),
[`event-preparations-v1.md`](../implementation/event-preparations-v1.md) och
[`event-participants-compact.md`](../implementation/event-participants-compact.md).

## 1. Laget och roller

- **Spelare får `team.roster.view`** (`609e9b3`): trigger vid aktivering av spelaruppdrag plus backfill. Rättar
  "Truppen är inte tillgänglig" för spelare (upptäckt fysiskt på Galaxy S25).
- **Inbjudningar som guide i tre steg** (`ccaa861`), pickers visar bara aktiv trupp och personer utan konto (`7c01f7d`).
- **Representation i två steg** (`16f5da2`, `99a5d68`, `65a043e`): laget markerar spelare som tillgängliga, mottagande
  lag begär, hemmalaget godkänner. Ett tvetydigt SQL-fel som stoppat varje representation sedan TEAM-06 rättades.
- **En redigeringsvy per person** (`a6035b6`), senare ombyggd: åtgärder och klubbens kontaktuppgifter ligger bakom
  pennan uppe till höger på medlemssidan; raden "Redigera profil" längst ner är borttagen.
- **Roller, titlar och positioner** (`3d46f05`): lägg till ledare (även sig själv eller klubbens ledare), byt mellan
  spelare och ledare, titlar (t.ex. Huvudtränare) och idrottsspecifika positioner i två nivåer. Flera roller i samma lag
  blir en lagkontext som visar titeln.
- **Behörigheter per ledare** med mallar (`3d46f05`, `20260929160000`, `20260929170000`): klubbens
  medlemsadministratörer hanterar ledare klubbövergripande.
- **Lagöversikt** (`c460ff0`): lagbild, aktiva inbjudningar/förfrågningar (bara för behöriga och bara när de finns),
  nästa händelse, senaste match.
- **Lägg till person** med roll, titel och position i samma dialog; en aktiv ledare listas inte också som tidigare spelare.
- **Lagprofil-dialogen** (`eb83321`) i samma stil som eventdialogen: helskärm på mobil, fast rubrikrad med Spara,
  sektionerna Lagbild, Om laget och Presentation, osparat-skydd.
- **Idrott ändras bara av klubbadministratör** (`20260930170000`, TEAM-11): `set_team_sport` kräver klubbskopad
  `club.memberships.manage`; övriga ser idrotten skrivskyddat.
- **Ny klubb från kontextväljaren** (`8bcb866`) och **Gör klubben officiell** i kontextväljaren (`eb83321`).

## 2. Kalender och event

- **Förberedelser v1 och Matchläge** (`3d46f05`, `20260928150000`, `20260928150100`).
- **Kalendern** (`a91b8e2`, `8d45f22`, `c460ff0`): "Vy och filter" i en knapp, Dag/Månad i listans rubrikrad, flera lag
  samtidigt, sparad standardvy, "Planerad" borttaget från korten (utkast får en liten ikon).
- **Ny eventdialog** (`f41d77e`) och **platser i tre delar**: anläggning, plan och valfritt fritextunderlag som
  återanvänds tillsammans (`20260930090000`).
- **Falskt sparfel vid kallelsesvar** rättat med en bekräftande omläsning (`d4bad8b`).

## 3. Inbox och notiser

- Inbox filtreras på aktivt lag som standard, klubbar kan fällas ihop, ny meddelandedialog väljer direkt/grupp
  automatiskt efter antal mottagare, filterdialogen är scrollbar och stängbar (`8d45f22`, `c460ff0`).
- Notiser kan markeras som lästa eller arkiveras direkt i listan (`f41d77e`).

## 4. Profil och konto

- **Egen profil** (`f41d77e`, `20260930120000`): namn, kontakt-e-post, telefon, adress och profilbild, som även kan
  tas med kameran (`image_picker`, `7daad16`). Synligt för personen själv och lagets ledare.
- **Inloggningsmejl byts bara via support** (`20260930130000`): supportgodkänd begäran plus bekräftelsemejl; en trigger
  på `auth.users` stoppar direkta byten.
- **Visningsnamnet slår igenom** i klubbens register, drawer och profil (`20260930140000`).
- **Virtuellt medlemskort** med fram- och baksida (adress), helskärm på mobil (`20260930150000`).
- **Profilflikar** Medlemsinfo, Statistik och Inställningar (`2956915`, `20260930160000`): statistiken gäller alltid den
  visade personen, även appstatistiken (skickade meddelanden, svarstid på kallelser, aktiva dagar och streak).
- **Inställningar** har flikarna Allmänt, Lag, Klubb (bara klubbadministratörer) och Profil (`a91b8e2`, `fe333da`).

## 5. Följarkonto (AUTH-08)

- Kontotypen `follower` (`core.profiles.account_type`, `20261001120000`) är till för att följa publika sidor och hör
  inte till något lag eller någon klubb.
- Kontot kan bara skapas på den publika sajten: webbläsaren postar till `/api/public/v1/account/sign-up`, som kontrollerar
  ursprung (`PUBLIC_SITE_ORIGINS`) och Turnstile (`signup`), skapar kontot och märker det via
  `api.mark_public_follower_account`, som bara `service_role` får köra. Bara helt nya konton utan klubbkoppling kan
  märkas; svaret är detsamma om adressen redan har ett konto.
- Godkännandet av villkor och integritetspolicy sparas med källan `web`.
- I appen hamnar följare i väntrummet. När en klubbkoppling blir aktiv blir kontot `member` (trigger).

## 6. Publik sajt

- **Klubbsajtsdesign** (`7daad16`): mörk klubbheader, hero, matchcenter, bildnyheter, matchkort med datumblock,
  partners och footer. Typsnitten Barlow Condensed och Inter är självhostade via `next/font`.
- **Klubbfärger** (`20261001090000`): huvud- och accentfärg väljs av klubbadministratörer. Sajten länkar
  `/api/public/v1/club-theme?p=…&a=…`, ett stylesheet som räknar fram läsbara varianter (ljus huvudfärg mörkas,
  accent som syns dåligt byts mot vitt i text). Inline-stilar används inte på grund av CSP.
- **TeamZones egna sidor** i samma stil (`1e551ec`): startsida med inloggningskort, personlig startsida, sök, 404,
  "inte publicerad" och juridiska sidor.
- **Matcher på lagsidan** (`20261001150000`, PUB-10): lagvalet "Visa matcher" publicerar alla matcher, både kommande
  och spelade, med titel och tid. Platsen visas bara om den publiceras per match, och en match som görs privat förblir dold.
- **Klubbmärke publikt** (`20261001170000`, PUB-11): aktivt märke för en publicerad klubb visas via
  `/media/public/<slumpad nyckel>`. Nyckeln byts när märket byts.
- **Rättelser:**
  - Lag som aldrig publicerats får en föreslagen webbadress, så spara-knappen kan aktiveras.
  - Kontaktformuläret på `public.teamzoneapp.se` avvisades tidigare eftersom bara `PUBLIC_ORIGIN`
    (`teamzoneapp.se`) godkändes; nu godkänns alla adresser i `PUBLIC_SITE_ORIGINS`.

## 7. Migrationer

Alla nedan är körda i testprojektet utom den sista.

| Migration | Innehåll |
|---|---|
| `20260926190000_team03_materialize_player_roster_view_capability` | Spelare får `team.roster.view` |
| `20260927120000` – `20260927180000` | Kontolänkflagga, representation i två steg, SQL-rättelse, självflagga och närvarosammanfattning |
| `20260928104134_event_participants_walk_in_attendance` | Närvaro för spontant deltagande |
| `20260928150000_event_preparations_v1`, `20260928150100_match_mode_v1` | Förberedelser och matchläge |
| `20260929090000` – `20260929190000` | Lagroller, titlar och positioner per idrott, ledarbehörigheter, klubbadministratörer hanterar ledare, medlemsprofil för ledare, egna titlar |
| `20260930090000_event_place_pitch_surface` | Anläggning, plan och underlag |
| `20260930120000` – `20260930160000` | Profilkontakt och profilbild, spärr för inloggningsmejl, namn till klubbens register, medlemskort, profilstatistik |
| `20260930170000_team_sport_club_admin_only` | Idrott endast för klubbadministratörer |
| `20261001090000_club_brand_colors` | Klubbfärger |
| `20261001120000_public_follower_accounts` | Följarkonton |
| `20261001150000_team_show_matches` | Visa matcher |
| `20261001170000_public_club_badge` | **Inte körd ännu.** Publikt klubbmärke |

## 8. Verifiering

- **Flutter:** `flutter analyze` utan anmärkningar och 524/524 tester (senaste fulla körning 2026-10-01). Nya eller
  uppdaterade test är bland annat `prof01_profile_test`, `msg09_inbox_layout_test`, `team02`, `team04`, `team08`, `team09`,
  `pub02_self_service_surface_test` och `pub03_editorial_surface_test`.
- **Publik sajt:** `npx tsc --noEmit` och 56/56 `node --test`, bland annat `club-theme.test.ts` och `public-signup.test.ts`.
  `next build` passerar.
- **Isolerade SQL-tester (PGlite):** `event_place`, `profile_contact`, `login_email_guard`, `profile_statistics`,
  `team_sport_admin`, `club_brand_colors`, `public_follower_accounts`, `team_show_matches` och `public_club_badge`
  (`node supabase/tests/<namn>.local.mjs`).
- **Live (skrivskyddat):**
  - ändringspunkterna för patchade funktioner kontrollerades före varje migration och att de tillämpats efteråt;
  - den publika registreringsrouten avvisar fel ursprung (503), falsk Turnstile-token (400) och ogiltig indata (400).
- **Produktägaren har verifierat:** sidornas design, lagpublicering efter rättelsen och att J-lagets matcher syns med
  "Visa matcher".

## 9. Driftsättning

- `app.teamzoneapp.se` (Firebase Hosting, `teamzoneapp-b02a2`): senast driftsatt 2026-10-01 med `fe333da`.
- `public.teamzoneapp.se` (App Hosting `teamzoneapp-public`, `europe-west4`): senast driftsatt 2026-10-01 med `83a0f6f`.
  Den publika delen av PUB-11 är ännu inte driftsatt.
- Galaxy S25 (debug-APK): senast installerad med `eb83321`. Senare ändringar är inte installerade.

## 10. Extern konfiguration

- `PUBLIC_SITE_ORIGINS=https://public.teamzoneapp.se` i `public-site/apphosting.yaml`.
- Cloudflare Turnstile-widgeten "TeamzoneApp public" tillåter `public.teamzoneapp.se` och `teamzoneapp.se`. Åtgärderna
  `contact` och `signup` verifieras server-side.
- Supabase Auth: `https://public.teamzoneapp.se/**` är tillåten redirect-URL för bekräftelsemejl.

## 11. Öppna punkter

- Kör `20261001170000_public_club_badge.sql` och driftsätt därefter app och publik sajt.
- Fysisk enhetsgrind för perioden (S25/tablet) återstår. S25 har inte de senaste versionerna.
- Den inloggade personliga startsidan i ny stil är inte visuellt kontrollerad av utvecklaren, eftersom det kräver inloggning.
- Ett helt registreringsflöde för följarkonto (mejlbekräftelse) är inte genomfört end-to-end.
- Publikt klubbmärke skalas inte om och metadata rensas inte; den generella bildbehandlaren (`public-media-worker`)
  saknar konfigurerad leverantör.
- Klubbfärgernas migration har kommentaren "PUB-08", men korten dokumenterar funktionen som PUB-12 för att undvika
  krock med PUB-08 (lagets händelsesynlighet).
