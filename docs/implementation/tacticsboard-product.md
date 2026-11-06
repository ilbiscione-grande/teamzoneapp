# Tacticsboard som fristående produkt – kartläggning och plan för två veckor

**Status 2026-11-02:** kartläggningen är klar. Beslut 1–5, 6 (adressen), 8 och 9 är tagna, se "Tagna beslut" nedan. Även beslut 7 och 10 är tagna, och produktens namn är bestämt. Det som återstår är CAPTCHA (11), hur snabbt support ska svara och valet av Supabase-projekt för produktionen. Buggen med `safeReturnTo` (punkt 4 i planen) är rättad, men inte committad. Betalning och registrering byggs först när de återstående besluten är tagna.

## Tagna beslut (2026-11-02)

- **Miljö:** produktionsmiljön sätts upp nu (fas 3–6), och Tacticsboard lanseras där.
- **Betalmodell:** prenumeration per person. TeamZone som helhet lanseras inte publikt än, så det finns inga TeamZone-ledare att ge särskilda villkor. Klubbarnas abonnemang väntar.
- **Pris (ändrat 2026-11-05):** 39 kr/mån inklusive moms. Årspriset är 390 kr (tio månadspriser), och under lanseringen ger årsabonnemanget 25 % rabatt första året, 292,50 kr. Priset gäller enskilda användare. Klubbar får ett högre pris senare, eftersom flera användare får tillgång samtidigt. AI blir ett tillägg senare och ingår inte i priset.
- **Provperiod:** 7 dagar utan kort. Därefter gäller läsläget tills man börjar betala.

- **Utan betalning:** helt låst. Man ser bara kontosidan och knappen för att börja betala. Inget tas bort, och allt fungerar igen så fort man betalar. Det ersätter läsläget som föreslås i avsnitt 3. Följdfråga: ska delade länkar och mappar som redan är delade sluta att fungera, eller bara projekten i editorn?
- **Adress:** `webtools.teamzoneapp.se/tacticsboard`. Tacticsboard följer med i den planerade flytten av Webtools till den adressen.
- **Moms:** hela EU med Stripe Tax. Det kräver registrering för OSS hos Skatteverket, som du gör.
- **Biblioteket:** betalande användare får publicera till hela biblioteket från start. Det kräver en knapp för att anmäla innehåll och en lista där du granskar anmälningarna. Det läggs till som punkt 16 i planen.

- **Låst konto och delningar:** när ett konto är låst fortsätter de länkar och mappar det har delat att fungera för andra. Det som stängs är ägarens egen åtkomst till Tacticsboard.
- **Namn:** "Teamzone Webtools" står med mindre bokstäver ovanför "TACTICSBOARD", som skrivs med versaler och med tydligt större text.
- **Lanseringskampanjen** gäller till och med 2026-12-31. Rabatten på 25 % på årsabonnemanget gäller bara första året. I Stripe blir det en kupong på 25 % som gäller en gång och som går att lösa in till och med 2026-12-31.
- **Säljare:** Tre 60 Grader, enskild näringsidkare, Plangränd 15, 574 34 Vetlanda. Stripe-kontot finns.
  - Organisationsnumret för en enskild firma är innehavarens personnummer. Det ska stå i villkoren och på kvittona, så det blir offentligt där. Du fyller i det själv.
  - Momsregistreringsnumret är SE + organisationsnumret + 01. Kontrollera hos Skatteverket att firman är registrerad för moms och F-skatt.
  - 2026-11-02 kunde Supabase inte verifiera momsnumret. Kontrollera numret i EU:s VIES. Är firman inte momsregistrerad, eller har den momsbefrielse, behöver det lösas innan Tacticsboard säljs med moms och OSS.
  - Firmans verksamhetsbeskrivning nämner i dag bilvård och folie. SNI-koden 58290 (utgivning av programvara) finns redan. Se över om verksamhetsbeskrivningen behöver ändras hos Bolagsverket.
- **Support:** `support@teamzoneapp.se`. Adressen tar emot mejl via ImprovMX, som vidarebefordrar till `teamzone.mobileapp@gmail.com` (`docs/operations/support_email_runbook.md`, MX kontrollerat 2026-11-03). Svar skickas som support@ från Gmail via Resends SMTP (sedan 2026-11-03). Löftet är svar inom två vardagar (beslutat 2026-11-04).

- **Produktionen får ett nytt Supabase-projekt**, `TeamzoneApp Production` i eu-north-1, enligt fas 3. Testprojektet `hgcshgunvooyudvrcpig` (eu-west-1) förblir testmiljö.

**Att tänka på i produktionsprojektet (fas 3):**
- Produktionsprojektet ska ligga i en Supabase-organisation som tillhör bolaget (Tre 60 Grader), med bolagets faktureringsuppgifter och momsregistreringsnummer. Organisationen ska vara på Pro, kräva tvåfaktorsinloggning och ha Supabases personuppgiftsbiträdesavtal (DPA) godkänt. Testprojektet kan ligga kvar där det ligger, eller flyttas dit senare.
- Listan över tillåtna adresser för omdirigering i Auth behöver även Webtools: `https://webtools.teamzoneapp.se/logga-in` (bekräftat konto och nytt lösenord). Fas 3 nämner i dag bara appens adresser. Testprojektet behöver motsvarande för hosted.app-adressen. Kontrollera att `?losenord=nytt` tillåts där.
- **Dubbla versionen `20270103090000` är löst (2026-11-03):** bokningsfilen heter nu `20270103080000_booking_forward_time.sql`. Den ligger kvar före `tactics_player_links` och före de senare bokningsmigrationerna, som bygger på dess kolumn `series_sequence`. I testprojektets historik står `20270103090000` bara en gång, för bokningsfilen. `20270103080000` är markerad som körd där (2026-11-03), och både bokningskolumnen och spelarlänkarna finns i testprojektet. Obs: verktyget väljer den lokala databasen som standard, så kommandon mot test kräver `--remote`.
- **Vault, Edge-hemligheter och funktioner i produktionen (2026-11-03):** Vault har sex namn. Edge har `TEAMZONE_ENV`, de två arbetartokens, `SUPPORT_PORTAL_URL`, `CONTACT_REPLY_SECRET` och `CONTACT_EMAIL_FROM_ADDRESS`. Alla 16 funktioner är driftsatta. Support- och notifieringsarbetaren svarar 200 varje minut. Kvar: Resend/SMTP och `SUPPORT_EMAIL_FROM`, Firebase för push, Stripe, övervakning, och en längre support-token (i dag 14 tecken). Instruktion: `docs/operations/production_secrets.md`.
- **Alla migrationer är körda i produktionen (2026-11-03):** alla 430 kördes med `db push --remote=zfxcblgnemuenaqjkaic --skip-vault`, och det kopplade projektet är fortfarande test. Historiken stämmer med alla 430. Det finns 0 klubbar och 0 användare, 5 moduler, 15 delade övningar, 11 cron-jobb och 1 Vault-hemlighet (`push_token_key`). Cron-jobben misslyckas tills Vault-hemligheterna är skapade, vilket är fas 3, punkt 4.
- **Kontrollen mot en tom databas är gjord (2026-11-03):** alla 430 migrationer och `seed.sql` gick igenom lokalt efter nollställningen. Bokningsmigrationerna är ännu inte committade men följer med i en `db push` från arbetskopian.
- **Två handkörda migrationer i testprojektet är nu markerade som körda (2026-11-03):** `20261022090000_sign_in_attempt_limits` och `20261128090000_tactics_live_idle`. Deras objekt fanns redan där. Det påverkar inte produktionen.
- **Lösenordslängd: minst 8 tecken (beslut 2026-11-03).** `supabase/config.toml`, `s01_auth_policy.md` och `production_provisioning.md` är ändrade från 12 till 8, så att de stämmer med webtools och Flutter-appen. Produktionen och testprojektet ställs in på 8 i Supabase under Authentication → Providers → Email. Alla teckentyper krävs (beslut 2026-11-03): liten och stor bokstav, siffra och specialtecken. `config.toml` har `password_requirements = "lower_upper_letters_digits_symbols"`, och webtools och appen kontrollerar samma regel med samma specialtecken som Supabase godkänner. I panelen: Authentication → Providers → Email → Password requirements → "Lowercase, uppercase letters, digits and symbols", både i test och produktion. Befintliga konton med svagare lösenord kan fortfarande logga in. Kravet gäller bara nya och bytta lösenord.

Följdfrågor om lanseringspriset (besvarade, se ovan): hur länge kampanjen pågår, och om halva priset gäller bara första året eller även när abonnemanget förnyas. I Stripe blir det enklast en kupong ("50 % första året") på årspriset.

**Mål:** Tacticsboard (`webtools/`, sidorna under `/tacticsboard`) säljs som en egen produkt med månadsavgift och är klart för lansering omkring **2026-11-16**. Funktionerna är de som finns i dag. Inga nya stora funktioner byggs före lanseringen.

## Sammanfattning

- **Själva verktyget fungerar redan utan TeamZone.** Allt som kräver ett lag eller en klubb är valfritt i gränssnittet och döljs eller förklaras när det saknas. Ett nytt konto utan lag kan skapa projekt, rita, animera, exportera, dela och hålla livelektioner.
- **Registrering och inloggning finns**, men de är byggda som "ett TeamZone-konto". Det som saknas för en köpare utanför TeamZone är lösenordsåterställning i webbläsaren, ett sätt att avsluta kontot och texter som inte förutsätter TeamZone-appen.
- **Det som saknas helt är det kommersiella:** betalning, prenumeration, provperiod, prissida, villkor för köp, kvitton och moms, support.
- **Det finns en grund för betalning med Stripe** (S10A: `core.billing_accounts`, `billing-checkout`, `stripe-webhook`, entitlements), men den gäller bara **klubbar**. En privatperson som köper Tacticsboard behöver ett betalkonto per person.
- **Den största frågan är miljön.** Allt körs i dag mot testdatabasen. Produktionsmiljön (faserna 3–6 i `docs/operations/production_provisioning.md`) är pausad. Betalande kunder i testmiljön blir svåra att flytta senare.
- **Villkoren och integritetspolicyn har platshållare** för bolagsnamn, organisationsnummer och adress. De måste fyllas i innan någon kan betala.

## Fråga 1: Vad saknas för att Tacticsboard ska fungera fristående?

### 1. Registrering och inloggning

Det som finns (`webtools/components/sign-in.tsx`, `account.tsx`, `shell.tsx`):
- Logga in och skapa konto med e-post och lösenord, med bekräftelse via mejl (Supabase Auth, PKCE).
- Godkännande av villkor och integritetspolicy vid första inloggningen (`LegalStep`).
- Inget krav på lag eller klubb. Sidan säger redan "Du behöver inte vara med i något lag".

Det som saknas:
- **Glömt lösenord.** Länken skickar i dag till TeamZone-appen (`links.appUrl`). En köpare som aldrig använt appen kommer inte vidare. Det behövs ett flöde i webtools för att begära en återställning och sätta ett nytt lösenord.
- **Byta lösenord och namn** i webtools. I dag hänvisar kontosidan till appen.
- **Avsluta kontot** (GDPR, rätt att bli raderad). Det finns en `person-erasure-worker`, men ingen knapp i webtools. Kontoavslut måste också avsluta prenumerationen.
- **Texterna** säger "TeamZone-konto" och "fungerar även i appen". Det är korrekt, men en köpare av Tacticsboard förstår kanske inte varför. Det beror på hur produkten ska heta utåt (beslut 4).
- **Skydd mot massregistrering.** En provperiod utan kort lockar till missbruk. Supabase har inbyggd CAPTCHA (hCaptcha/Turnstile) som kan slås på för registreringen. Det är ditt beslut och görs i Supabase.
- **Mejlen från Supabase** (bekräftelse och återställning) ska ha rätt avsändare och text. Kontrollera mallarna och SMTP i Supabase-projektet.

### 2. Det som kräver ett lag eller en klubb i TeamZone i dag

| Funktion | Kräver | Utan TeamZone i dag | Behövs före lansering |
|---|---|---|---|
| Truppen i panelen "Lag" (`SquadPanel`, `use-squad.ts`) | Projektet kopplat till ett lag där du är ledare | Texten "Koppla projektet till ett av dina lag i TeamZone…" | Ny text för den som inte har TeamZone, eller ett enkelt sätt att skriva in namn själv (kan vänta) |
| Välja lag i projektet (`TopBar`, `NewProjectDialog`) | Ledarroll i ett lag | Väljaren döljs | Inget |
| Lagets tavlor och ledarnas rättigheter | Ledarroll | Avsnittet döljs | Inget |
| Lägga tavlan i ett träningspass (`TrainingLinkDialog`) | Projektet kopplat till ett lag | Förklarande text | Dölj knappen när du inte har något lag |
| Spelarlänkar (`PlayerLink`) | Lag | Döljs | Inget |
| Klubbens märke i branding (`BrandingFields`) | Klubbroll | Bara egen logga | Inget |
| Klubbens lista i biblioteket, publicera till en klubb | Klubbroll | Döljs, bara "hela biblioteket" | Inget |
| TeamZones bibliotek (läsa, favoriter, publicera till alla) | Inget | Fungerar | Beslut: får betalande användare utanför TeamZone publicera till alla? Då behövs ett sätt att anmäla innehåll |
| Livelektioner, delade länkar, mappar, versioner, export | Inget | Fungerar | Inget |

**Slutsats:** inget i kopplingen till TeamZone stoppar en fristående användare. Det som behövs är texter och att dölja knappar som inte går att använda.

### 3. Betalning och prenumeration

Det som finns (S10A, augusti 2026):
- Tabeller för betalkonto, prenumeration, rader och entitlements, med versionerad prisbok.
- Edge-funktionerna `billing-checkout` (Stripe Checkout) och `stripe-webhook` (signaturkontroll, dubblettskydd, ordning på händelser).
- Regler för grace och läsläge (PAR-BILL-02): 14 dagars grace, sedan läsläge och export, och ingen data raderas.
- Allt är knutet till `club_id`. Det finns ingen prenumeration per person.

Det som behöver byggas:
1. **Betalkonto per person.** Prenumerationen tecknas av ett konto (`profile_id`) och ger entitlementen `webtool.tacticsboard`. Antingen en egen tabell för personliga konton eller en utökning av `billing_accounts` med en ägare som är en klubb *eller* en person. Den egna tabellen rör inte klubbarnas befintliga flöde och rekommenderas.
2. **Checkout** med Stripe Checkout (Stripes egen betalsida) från webtools. Stripe hanterar kort, Apple Pay och Google Pay, 3-D Secure och kvitton. Inga kortuppgifter passerar TeamZone.
3. **Stripe Customer Portal** för att byta kort, se kvitton och säga upp. Det sparar mycket egen kod.
4. **Webhooken** uppdaterar prenumerationen och räknar om entitlementen. Den befintliga funktionen byggs ut, den skrivs inte om.
5. **Kontrollen görs på servern.** Varje skrivande RPC i Tacticsboard (`create_tactics_project`, `save_tactics_project`, publicera, starta livelektion) kontrollerar entitlementen. Gränssnittet visar en tydlig ruta när prenumerationen saknas, men gränssnittet är aldrig skyddet.
6. **Provperioden** startas en gång per konto och kan inte startas igen.

**Byggt för punkt 6 (2026-11-03), migration `20270204090000_tacticsboard_personal_billing`:**
- `core.personal_billing_accounts`, en rad per person. Raden skapas när provperioden startar och sparar start och slut (7 dagar). Den tas aldrig bort, så provperioden kan inte startas igen.
- `core.personal_billing_subscriptions`, personens prenumeration. Den skrivs bara av webhooken (punkt 7), och Stripes referenser sparas som hash som i S10A. Tillstånden är `active`, `grace`, `ended` och `unknown`.
- `internal.personal_entitlement_status` ger `write` eller `denied`. `write` gäller vid aktiv prenumeration, under grace tills `grace_ends_at` och under provperioden. Annars är kontot helt låst. Inget raderas.
- `internal.actor_has_tacticsboard()` är spärren som de skrivande RPC:erna ska anropa i punkt 8.
- `api.get_my_tacticsboard_access()` och `api.start_tacticsboard_trial()` finns för webtools. Starten är idempotent och loggas i `audit.command_events`. Gäster i livelektioner (anonym inloggning) får ingen provperiod.
- Provperioden startar första gången personen öppnar Tacticsboard, inte när kontot skapas. Då förbrukar inte ett konto som bara används i TeamZone-appen sin provperiod. Webtools anropar starten i punkt 8 och 9.
- Tabellerna är stängda för klienter. Allt går via RPC:erna.

**Byggt för punkt 7 (2026-11-03), migration `20270205090000_tacticsboard_personal_checkout`:**
- **Flödet:** webtools anropar Edge-funktionen `tacticsboard-billing` med `{action: "checkout", interval: "month"|"year", idempotencyKey}` eller `{action: "portal"}`. Svaret är `{url}` till Stripes sida.
  - Funktionen förbereder köpet som personen själv (`api.prepare_tacticsboard_checkout`). Därefter hämtar den pris, kupong och kund som server (`api.claim_tacticsboard_checkout`). Begäran innehåller aldrig något pris.
  - Ett andra köp nekas med `already_subscribed` medan prenumerationen eller grace gäller.
- **Stripe Checkout:**
  - svenska, Stripe Tax (`automatic_tax`) och momsnummer för företag
  - adressen krävs
  - kunden återanvänds, och annars förifylls e-postadressen
  - kupongen läggs på så länge `coupon_ends_at` inte har passerat
  - Återstår mer än 48 timmar av provperioden, sätts den som `trial_end`, så att den som köper tidigt inte betalar för de dagarna.
  - Tillbaka till `/konto?betalning=klar` eller `/konto?betalning=avbruten`.
- **Customer Portal** öppnas för personens egen Stripe-kund. Därifrån kommer man tillbaka till `/konto`.
- **Live eller test** avgörs av Stripe-nyckeln (`sk_live_`/`rk_live_` eller `sk_test_`/`rk_test_`). Ett testpris kan aldrig användas med en skarp nyckel.
- **Webhooken:** `stripe-webhook` skickar händelser med `metadata.teamzone_product = webtool.tacticsboard` till `api.ingest_tacticsboard_stripe_event`. Övriga händelser går till klubbarnas S10A som förut.
  - Hanteras: `checkout.session.completed`, `customer.subscription.created`, `customer.subscription.updated` och `customer.subscription.deleted`. De kan komma i vilken ordning som helst.
  - Dubbletter, äldre händelser och främmande händelser (utan köp, med okänt pris eller fel läge) tas bort.
  - En äldre prenumeration ersätter aldrig en nyare som fortfarande ger åtkomst.
- **Tillstånden från Stripe:**
  - `active` och `trialing` ger `active`.
  - `past_due` och `unpaid` ger `grace` i 14 dagar, räknat från första misslyckandet.
  - `canceled`, `incomplete_expired`, `paused` och borttagen ger `ended`.
  - Allt annat ger `unknown`, utan åtkomst.
- **Provperioden:** den som köpt utan provperiod får ingen provperiod senare.
- **Ursprung:** Edge-funktionen godkänner `https://webtools.teamzoneapp.se` och de adresser som `TEAMZONE_EXTRA_WEB_ORIGINS` listar. I test måste den listan innehålla Webtools hosted.app-adress.
- **Det här gör du i Stripe (testläge först):**
  1. Produkten "Tacticsboard" med två återkommande priser: 39 kr/mån och 390 kr/år, med moms inräknad (tax behavior: inclusive).
  2. Kupongen: 25 %, gäller en gång, går att lösa in till och med 2026-12-31.
  3. Slå på Stripe Tax.
  4. Lägg till de fyra händelserna ovan på webhooken som pekar på `stripe-webhook`.
  5. Customer Portal: tillåt byte av kort, kvitton och uppsägning vid periodens slut.
- **Priserna i testprojektet är inlagda (2026-11-03):** månadspriset `price_1UXkSR4Skh2WBbLCRSPTcGdy` och årspriset `price_1UXkTK4Skh2WBbLCfJ3SDRW2` med kupongen `LANSERING50` till och med 2026-12-31. Båda är i testläge (`livemode = false`).  Det är de gamla priserna (79 och 790 kr, 50 %) och de behöver bytas i testläget innan e2e-testet fortsätter. Produktionen får de skarpa priserna i punkt 15.
- **Ett köp är provat hela vägen i test (2026-11-03):** månadspriset med testkort, sedan `checkout.session.completed` och `customer.subscription.created` hanterade. Prenumerationen blev `active`, och provperiodens rest fördes över (perioden slutar 2026-11-10). Två fel fanns först:
  - Stripe-nyckeln i test hörde till klubbarnas gamla sandlåda och byttes.
  - Signing secret hörde till en annan endpoint, så webhooken svarade 400 `invalid_signature`. Den byttes, och händelserna skickades igen.
- **Så läggs priserna in** (bara id:n, inga hemligheter):
  ```sql
  insert into internal.personal_billing_prices (billing_interval, livemode, provider_price_ref, provider_coupon_ref, coupon_ends_at)
  values ('month', false, 'price_…', null, null),
         ('year', false, 'price_…', '<kupongens id>', '2027-01-01 00:00+01');
  ```

**Byggt för punkt 8 (2026-11-03), migration `20270206090000_tacticsboard_write_gate`:**
- **Spärren i databasen:** `internal.require_tacticsboard()` stoppar med `tacticsboard_locked` när personen varken har provperiod, prenumeration eller grace. Den utloggade får den inre funktionens eget svar.
  - 44 api-funktioner anropar den först. Det gäller allt ägaren gör med sina egna projekt, mappar, mallar, versioner och sitt bibliotek, och även läsningar.
  - Inne i funktionerna är inget ändrat.
- **Det som fortsätter att fungera för en låst ägare och för andra:**
  - delade länkar och mappar (`get_shared_tactics*`)
  - livelektioner som redan har startat: att gå med, frågor, chatt, ritning, ordet och att avsluta. Att starta en ny är spärrat.
  - att ta tillbaka: återkalla en länk och ta bort något ur biblioteket
  - granskningen av anmälningar
  - TeamZones egna flöden för matchplaner och träningspass. De anropar internal-funktionerna och påverkas inte.
- **Testet** `supabase/tests/tacticsboard_write_gate.local.mjs` kontrollerar två saker:
  - Den senaste definitionen av varje spärrad funktion, i alla migrationer, anropar fortfarande spärren.
  - En ny api-funktion för Tacticsboard måste placeras antingen bland de spärrade eller i listan över öppna.
- **I webtools:**
  - `RequireTacticsboard` ligger runt startsidan, biblioteket, mappen och editorn.
  - Första besöket startar provperioden.
  - Utan åtkomst visas "Provperioden är slut" eller "Prenumerationen har upphört", med knapparna för månad och år, som går till Stripe Checkout.
  - En rad visar provperiodens dagar, en misslyckad betalning (med "Uppdatera kortet", som öppnar kundportalen) eller en uppsägning.
  - Reglerna finns i `lib/tactics/access.ts` och testas i `tests/tactics-access.test.ts`.
- **Ordningen vid driftsättning:** migrationen och webtools måste ut tillsammans. Kommer migrationen först, låses den driftsatta Tacticsboard, eftersom den gamla webtools aldrig startar någon provperiod.

**Byggt för punkt 9 (2026-11-03), avsluta kontot (beslut: en egen knapp, automatiskt):**
- **Kontosidan** har avsnittet "Avsluta kontot". Personen skriver AVSLUTA för att bekräfta. Texten säger tre saker: vad som tas bort, att prenumerationen avslutas direkt utan återbetalning och att kvittona finns kvar hos Stripe.
- **Edge-funktionen `account-deletion`** gör så här:
  1. Kontrollerar med en provkörning i databasen att raderingen går igenom. Provkörningen gör allt och rullar sedan tillbaka.
  2. Avslutar personens Stripe-prenumerationer direkt.
  3. Raderar datan (`api.erase_own_account`).
  4. Tar bort Auth-användaren.

  Misslyckas steg 4 kan personen försöka igen. Datan är redan borta, och då tas bara användaren bort.
- **Raderingen** (migration `20270207090000_account_self_erasure`):
  - Tacticsboards projekt, versioner, länkar, livelektioner, mappar, mallar, biblioteket och det som publicerats, med deras val och favoriter.
  - Betalkontot, kunden, godkännandena av villkoren och inställningarna, som följer med genom cascade.
  - Loggraderna blir anonyma.
- **Konton som är kopplade till en klubb** får `club_linked` och hänvisas till den granskade raderingen (TEAM-08) i appen.
- **Om andra uppgifter blockerar** raderingen får personen `needs_support` och hänvisas till support. Ingenting ändras då.
- **Provat lokalt i Postgres:** provkörningen ändrar inget, den riktiga raderingen lämnar 0 rader kvar, en andra körning fungerar, Auth-användaren går att ta bort efteråt, och ett blockerat konto lämnas orört.

**Förslag på vad som gäller utan betalning** (följer PAR-BILL-02):
- Under provperioden och med aktiv prenumeration: allt.
- 14 dagar efter misslyckad betalning (grace): allt, med en varning.
- Därefter (läsläge): du kan öppna, titta, presentera och exportera PDF och video av dina egna projekt. Du kan inte skapa, spara ändringar, publicera eller starta livelektioner. Delade länkar och mappar som redan är delade fortsätter att fungera, så att ett lag som fått en länk inte drabbas.
- Ingenting raderas. När betalningen kommer tillbaka fungerar allt som förut.

**TeamZone-användare som redan använder Tacticsboard** i dag (beta) behöver ett beslut: gratis under betan och sedan betalt, gratis för den som är ledare i ett TeamZone-lag eller via klubbens abonnemang senare (beslut 2).

### 4. Prissättning

Inget pris är satt för Tacticsboard. Klubbarnas prisbok (Small 199 kr/mån och uppåt) gäller inte en enskild tränare.

Som jämförelse tar liknande taktiktavlor på webben ofta ungefär 50–150 kr i månaden för en tränare. Det är ett ungefärligt intervall, inte en undersökning, och du bör jämföra med de konkurrenter du själv ser som viktiga innan priset sätts.

Förslag att ta ställning till:
- **Ett pris**, till exempel 79 kr/mån inklusive moms, och ett årspris som motsvarar tio månader (790 kr/år). Det följer klubbarnas regel att årspriset är tio månadspriser.
- En gratisnivå är möjlig men gör lanseringen större (gränser att bygga och förklara). Rekommendationen är bara provperiod vid lansering.

### 5. Landningssida och adress

- I dag nås Tacticsboard via katalogen på Webtools (`app/page.tsx`, `lib/apps.ts`) på den tillfälliga adressen `teamzoneapp-webtools--teamzoneapp-b02a2.europe-west4.hosted.app`. Den adressen går inte att sälja på.
- Det behövs:
  - en **produktsida** för Tacticsboard med bilder eller video, funktioner, pris, "Prova gratis" och vanliga frågor
  - en **riktig adress**: flytten av Webtools till en egen domän, som redan väntar (minnet `webtools-portal`). Vid flytten ändras `NEXT_PUBLIC_WEBTOOLS_URL`, Supabase-listan över tillåtna adresser för omdirigering och App Hosting-domänen.
  - **delningsbilder och titel** för produktsidan, och att den kan indexeras av sökmotorer. Villkorssidorna har i dag `robots: noindex`, och det är rätt.

### 6. Villkor, integritetspolicy och GDPR

- `public-site/app/villkor` och `integritet` gäller hela TeamZone och har platshållare: `[JURIDISKT NAMN]`, `[ORG.NR]`, `[POSTADRESS]` och en platshållare om minimiålder. **Det måste fyllas i innan någon betalar.**
- Det som behöver läggas till för köp:
  - **Prenumerationsvillkor:** pris, period, förnyelse, uppsägning, vad som händer efter uppsägning (läsläge, export) och prisändringar.
  - **Ångerrätt för konsumenter.** Vid digitala tjänster har konsumenten 14 dagars ångerrätt. Den kan bara gå förlorad om kunden uttryckligen samtycker till att tjänsten börjar direkt och bekräftar att ångerrätten då upphör. Det samtycket behöver finnas i köpflödet. Låt någon med juridisk kunskap granska texten.
  - **Integritetspolicyn:** Stripe som mottagare av betaluppgifter (personuppgiftsbiträde eller självständigt ansvarig för betalningen), vilka uppgifter som sparas om prenumerationen och hur länge (bokföringen kräver sju år för kvitton och fakturor).
- **GDPR i produkten:** avsluta kontot (se avsnitt 1), exportera sina projekt (finns som fil-export per projekt i dag), och att spelarnamn på tavlor är personuppgifter som användaren själv ansvarar för.
- Villkoren versionshanteras redan och kräver nytt godkännande (`accept_current_legal`). Ett tillägg för Tacticsboard bör godkännas vid köpet, inte vid första inloggningen.

### 7. Kvitton och moms

- **Kvitton:** Stripe skickar kvitton och fakturor i mejl när det slås på i Stripe. De visas också i Customer Portal. Kvittot ska ha bolagets namn, organisationsnummer, momsregistreringsnummer och adress, som läggs in i Stripe.
- **Moms:** 25 % moms på digitala tjänster i Sverige. Säljer du till konsumenter i andra EU-länder gäller det landets moms, och då behövs **OSS** (en momsdeklaration via Skatteverket) eller att försäljningen begränsas till Sverige vid lanseringen.
  - Enklast: **Stripe Tax** räknar ut momsen per land och hjälper med underlaget. Det kostar en avgift per transaktion.
  - Alternativt: bara Sverige vid lansering, priset visas inklusive 25 % moms, och adresslandet krävs i Checkout.
- **Bokföring:** Stripes rapporter och utbetalningar bokförs. Det ligger utanför appen.
- Tala gärna med din redovisningskonsult om OSS och om Stripe Tax behövs.

### 8. Onboarding och tomt läge

Det som finns:
- Startsidan har ett "Kom igång"-läge när du inte har några projekt (`TacticsHome`, `tb-welcome`) med snabbstart per typ och biblioteket.
- Hjälpdialog (`HelpDialog`) och verktygstips (`ToolHint`).

Det som saknas:
- **Första mötet efter köpet:** ett exempelprojekt eller en färdig mall som öppnas direkt, så att den nya användaren ser animation och export på en gång.
- **Provperiodens status** syns inte någonstans: "11 dagar kvar av provperioden", med en knapp för att börja prenumerera.
- **Texter som förutsätter TeamZone** ("TeamZones bibliotek", "Lag i TeamZone", panelen "Lag") behöver ses över för den som inte har appen.
- Sidhuvudet säger "TeamZone Webtools – Verktyg för lag och klubbar". Det kan stå kvar, men Tacticsboard bör synas som produkt.

### 9. Support

Det finns en `support-email-worker` och en `contact-inbound` i Supabase, men ingen kontaktväg från webtools.
- **Vid lansering räcker:** en supportadress (till exempel `support@…`) i sidfoten, i hjälpdialogen och i kvittot, och en enkel sida med vanliga frågor.
- **Kan vänta:** ett kontaktformulär i appen, chatt, statussida.
- Löftet är svar inom två vardagar (beslutat 2026-11-04). Det står i `webtools/lib/support.ts` och ska också stå i villkoren (punkt 11).

## Fråga 2: Vad behöver putsas och fixas?

Genomgången gjordes 2026-11-02 i koden och i förhandsvisningen av `/tacticsboard/demo` i mobilstorlek (375×812). `node --test tests/*.test.ts` gav 216 godkända tester av 216, och `npx tsc --noEmit` gav inga fel.

### Buggar

1. **Tillbaka efter inloggning tappas för biblioteket och mappar.** `safeReturnTo` i `webtools/lib/apps.ts` godkänner `/tacticsboard` och `/tacticsboard/<id>`, men inte `/tacticsboard/bibliotek` eller `/tacticsboard/mapp/<id>`, som båda skickar med just de adresserna (`app/tacticsboard/bibliotek/page.tsx`, `app/tacticsboard/mapp/[id]/page.tsx`). Den som loggar in därifrån hamnar på Webtools startsida. Det är en liten rättelse med ett test.
2. **Glömt lösenord leder till appen** (se avsnitt 1). För en fristående köpare är det ett stopp.

### Ofärdiga flöden

- **Panelen "Lag" utan lag:** löst. Fliken visar formationerna, och delen om truppen syns bara för den som har ett lag (kontrollerat 2026-11-06).
- **"Lägg i träning":** löst. Valet syns bara i ett träningsprojekt för den som har ett lag.
- **Biblioteket som gemenskap:** det finns inget sätt att anmäla olämpligt innehåll. När främlingar kan publicera till alla behövs det, eller så stängs publicering till alla av för konton utan lag tills vidare.
- **Steg 5 i kopplingen till TeamZone** (`tacticsboard-teamzone-link.md`) och AI-funktionen (`tacticsboard-ai.md`) är planerade och påverkar inte lanseringen.

### Mobil och surfplatta

- I mobil (375 px bred) ryms editorn utan sidledsscroll. Tavlan, tidslinjen, verktygsraden för telefon och panelflikarna får plats.
- **Toppraden i mobil:** löst med "Mer"-menyn. Kontrollerat 2026-11-06 i 375 och 320 px. Då rättades också att knapparna för en misslyckad sparning hamnade utanför skärmen, och att Inställningar var för bred.
- Tidslinjens förloppsstapel (`tb-progress`): löst, den sticker inte längre ut.
- **Surfplatta och riktiga pekskärmar:** provade av Thomas 2026-11-06.

### Prestanda

Mätt 2026-11-06 med en simulerad mobil: 1,6 Mbit/s, 150 ms svarstid och fyra gånger långsammare processor.

| Sida | Första innehåll | Största innehåll | Blockerad tid | Sidhopp | Data |
|---|---|---|---|---|---|
| Produktsidan före rättelsen (produktion) | 1,6 s | 5,8 s | 0,25 s | 0,22 | 1,1 MB, med filmen 1,6 MB |
| Produktsidan efter rättelsen (lokalt) | 2,0 s | 3,8 s | 0,34 s | 0 | 1,1 MB utan film |
| Inloggningen | 1,4 s | 3,0 s | 0,27 s | 0 | 0,3 MB |
| Editorn (lokalt, klar att använda 4,5 s) | 1,4 s | 4,1 s | 0,70 s | 0 | 0,6 MB, varav 435 kB JavaScript |
| Startsidan teamzoneapp.se | 1,8 s | 1,8 s | 0,28 s | 0 | 0,5 MB |

- **Produktsidan** visade "Laddar…" tills kontot var läst, och hoppade sedan. Nu visas den direkt från servern, och filmen laddas inte på telefon, där den ändå ligger bakom en mörk yta. Den är också öppen för sökmotorer. Lokala och produktionens siffror är inte helt jämförbara.
- **Stort projekt** (20 tavlor, 40 frames, 25 objekt per frame, 3,9 MB text): att byta tavla tar under 75 ms, och en dragning cirka 34 ms per steg, med fyra gånger långsammare processor. Projektgränsen är 4 MB komprimerat. Riktiga ritningar utan objekt är inte med i provet.
- **PDF** med 20 tavlor och 15 frames, en per sida: 59 sekunder på dator. Provet är inte gjort på telefon.
- **Livelektion** är beräknad, inte provad med många deltagare. Produktionen är på Pro med spending cap: 500 samtidiga anslutningar och 500 meddelanden per sekund, och gränserna går inte att höja med spending cap på. Varje mottagare räknas som ett meddelande. En lektion tar 12 deltagare (beslut 2026-11-06), vilket räcker till till exempel backlinjen eller startelvan. Fler deltagare blir en premiumfunktion som köps till. Databasen kontrollerar taket när någon går med (migrationen `20270212090000`), och den som redan har gått med behåller sin plats, men den som lämnar frigör ingen. Läraren skickar högst 15 drag per sekund, och pekaren, 10 per sekund, är av under dragning. Det ger högst 195 meddelanden per sekund för en full lektion, så två fulla lektioner ryms samtidigt.

### Drift och säkerhet

- **Miljön:** testmiljö i dag, se beslut 1.
- **Kostnader som växer med användare:** Supabase-planen (Realtime, lagring och databas), App Hosting och Stripes avgifter.
- **CSP:** Stripe Checkout öppnas genom en omdirigering, så CSP behöver inte ändras. Stripe.js i sidan kräver däremot ändringar. Rekommendationen är omdirigering.
- **Övervakning:** fel i webhooken måste märkas. Det finns `critical-flow-monitor` och kan användas.

## Prioriterad plan för två veckor

### Måste vara med vid lansering

| # | Arbete | Vem | Ungefär |
|---|---|---|---|
| 1 | Besluten nedan | Du | Dag 1 |
| 2 | Produktionsmiljön, om beslut 1 blir ja (fas 3–6) | Du skapar Supabase-projektet och DNS, jag förbereder och verifierar | 2–3 dagar, delvis parallellt |
| 3 | Stripe-kontot aktiverat med bolagsuppgifterna, produkt och pris i testläge | Du (jag får inte skapa konton eller hantera riktiga uppgifter) | Dag 1–3 |
| 4 | Rätta `safeReturnTo` för biblioteket och mappar, med test (klart 2026-11-02) | Jag | Timmar |
| 5 | Glömt lösenord och byte av lösenord i webtools (byggt 2026-11-02: `components/password.tsx`, länken går till `/logga-in?losenord=nytt`. Hela flödet med mejl är inte provat) | Jag | 1 dag |
| 6 | Betalkonto per person, entitlementen `webtool.tacticsboard` och provperioden (migration som du kör). Skrivet 2026-11-03: `20270204090000_tacticsboard_personal_billing.sql`, provat i PGlite (`supabase/tests/tacticsboard_personal_billing.local.mjs`) och lokalt. Kört i test 2026-11-03 (tabeller, RLS, funktioner och rättigheter kontrollerade). Inte kört i produktion | Jag skriver, du kör SQL | 2 dagar |
| 7 | Checkout, Customer Portal och webhooken (bygger på S10A). Skrivet 2026-11-03: migrationen `20270205090000_tacticsboard_personal_checkout.sql` (körd lokalt och i test), Edge-funktionen `tacticsboard-billing` och vägvalet i `stripe-webhook` (ingen av dem driftsatt). Kvar: priserna i Stripe och raderna i `internal.personal_billing_prices`, händelserna på webhooken och inställningarna för Customer Portal, se "Byggt för punkt 7" | Jag | 2 dagar |
| 8 | Kontroll i servern på alla skrivande RPC:er, och läsläget i gränssnittet. Skrivet 2026-11-03: migrationen `20270206090000_tacticsboard_write_gate.sql` och `RequireTacticsboard` på de fyra sidorna i webtools. Committat som `00cf210`. Driftsatt i test 2026-11-03: webtools först, sedan migrationen (44 spärrade funktioner, 31 öppna). Inte i produktion | Jag | 1–2 dagar |
| 9 | Kontosidan: prenumerationens status, provperiodens dagar kvar, hantera betalning, avsluta kontot. Skrivet 2026-11-03 (inte driftsatt): `TacticsboardSubscription` under Abonnemang visar prenumerationen och nästa betalning, uppsägningen, en misslyckad betalning, provperiodens dagar eller "Prova gratis", med knapparna för Stripes portal och köp. Efter köpet väntar sidan på webhooken i upp till 20 sekunder. Avsluta kontot är byggt samma dag, se "Byggt för punkt 9". Migrationen, funktionen `account-deletion` och webtools är driftsatta i test (`9b645fa`). Provat i test 2026-11-03: kontosidan, uppsägningen i Stripes portal och avslutet av ett nytt konto. Auth-användaren och profilen är borta och loggraden `account.self_erased.v1` finns | Jag | 1 dag |
| 10 | Produktsida med pris och "Prova gratis". Byggt 2026-11-03 (inte committat eller driftsatt): `TacticsProduct` renderas på servern på `/appar/tacticsboard` och visas för utloggade på `/tacticsboard`, där inloggade kommer direkt till sina projekt. Den har rubriken med "Teamzone Webtools" ovanför "TACTICSBOARD", sex punkter om funktionerna, priserna med lanseringskampanjen (försvinner efter 2026-12-31, sidan byggs om varje timme) och fyra vanliga frågor. "Prova gratis i 7 dagar" går till registreringen och tillbaka till Tacticsboard. Filmen och tre skärmbilder ligger i `webtools/public/tacticsboard/` sedan 2026-11-03. Filmen spelas i rubriken och bilderna visas under punkterna. Film och bilder är omgjorda 2026-11-06 med påhittade spelare, se [tacticsboard-english.md](tacticsboard-english.md). Kvar: din granskning av texterna | Jag bygger, du ger bilder, texter och pris | 1–2 dagar |
| 11 | Villkor, prenumerationsvillkor, ångerrätt och integritetspolicy med riktiga bolagsuppgifter. Utkast 2026-11-04 (beslut: egna villkor som godkänns vid köpet, och en obligatorisk kryssruta i Checkout): `public-site/app/villkor/tacticsboard` (version 2026-11-04), säljaren och support i de allmänna villkoren och integritetspolicyn, leverantörerna och avsnittet 4 a om Tacticsboard i policyn. Checkout kräver godkännandet (`consent_collection`, text i `_shared/tacticsboard_billing.ts`), och Stripe behöver villkorens adress under Public details innan funktionen driftsätts. Kvar: organisations- och momsnummer, juridisk granskning av ångerrätten och ansvaret, leverantörernas behandlingsplatser, och nya versionsrader i `internal.legal_document_versions` när texterna är klara | Du (gärna med juridisk granskning), jag lägger in dem | Parallellt |
| 12 | Texter utan TeamZone, dölj det som inte går att använda, toppraden i mobil. Byggt 2026-11-03 (inte committat eller driftsatt): inloggningen, villkorssteget och kontosidan säger "konto" i stället för "TeamZone-konto", och "TeamZones bibliotek" heter "Biblioteket". Truppen i panelen Lag och "Lägg i ett pass" visas bara för den som är med i ett lag. I mobil är "+ Tavla" bara "+", tavlan du är på scrollas fram, och förloppsstapeln sticker inte längre ut. Webtools startsida och sidorna för de andra apparna är inte ändrade | Jag | 1 dag |
| 13 | Supportadress och vanliga frågor. Byggt 2026-11-04 (inte committat eller driftsatt): `webtools/lib/support.ts` har adressen och löftet om svar inom två vardagar. De visas i sidfoten ("Support"), i hjälpdialogen i Tacticsboard och som en femte vanlig fråga på produktsidan. Kvar: löftet i villkoren, som du skriver i punkt 11 | Du ger adressen, jag lägger in den | Timmar |
| 14 | Prov från början till slut i Stripes testläge: registrering, provperiod, köp, misslyckad betalning, läsläge, uppsägning, kontoavslut. Provschemat finns i `tacticsboard-e2e-test.md` (2026-11-04), inte genomfört | Jag, och du på riktig telefon och iPad | 1 dag |
| 15 | Byte till Stripes skarpa läge, domänen, deploy. Checklistan och läget i produktionen finns i `tacticsboard-production.md` (2026-11-04) | Du säger ja per steg | Sista dagarna |
| 16 | Anmäla innehåll i biblioteket, och en lista där du granskar anmälningarna. Byggt 2026-11-03 (inte committat eller driftsatt i webtools): anmälan, att tre anmälningar döljer innehållet och supportens beslut fanns sedan `20261214090000`. Nytt: migrationen `20270208090000_tactics_shared_report_review.sql` (supporten ser innehållet helt, även när det är dolt; körd i test 2026-11-03), dialogen "Anmäl" med skäl i biblioteket, och sidan `/tacticsboard/granska` för supportkonton med beslutet "Dölj ur biblioteket" eller "Behåll" och en motivering till loggen. I test är `coach.emilson@gmail.com` support. Produktionen har inget supportkonto än, det läggs in i `internal.support_admins` i punkt 15. Inget mejl skickas till supporten när något anmäls | Jag skriver, du kör SQL | 1 dag |

**Förslag på ordning:**
- **Vecka 1 (3–9 nov):** 1, 3, 4, 5, 6, 7 och 2 parallellt. Allt i Stripes testläge.
- **Vecka 2 (10–16 nov):** 8, 9, 10, 11, 12, 13, 14, sedan 15.

Det mesta av risken ligger i 2, 3 och 11, som kräver dig och utomstående (Supabase, Stripe, DNS, juridik). De bör starta första dagen.

### Kan vänta till efter lanseringen

- Gratisnivå med gränser
- Rabattkoder, kampanjer, klubbpris och paket med andra Webtools-appar
- Tacticsboard via klubbens abonnemang i TeamZone (bygger på S10A för klubbar)
- Egen trupp utan TeamZone (skriva in namn och nummer)
- Anmälan av innehåll i biblioteket, om publicering till alla stängs av för konton utan lag vid lansering
- Kontaktformulär i appen, chatt och statussida
- Andra språk än svenska och engelska (engelska: se [tacticsboard-english.md](tacticsboard-english.md))
- Steg 5 i kopplingen till TeamZone, och AI-funktionen
- Mer djupgående prestandaarbete efter mätningarna

## Beslut du behöver ta

Beslut 1–4 är tagna, se "Tagna beslut" överst. Frågorna står kvar här som de ställdes.

1. **Miljö:** ska vi sätta upp produktionsmiljön nu (fas 3–6, Supabase Pro i eu-north-1, med en månadskostnad) och lansera Tacticsboard där? Eller ska de första kunderna ligga i dagens testmiljö och flyttas senare? *Rekommendation: produktion nu. Betalande kunders konton och projekt bör inte ligga i en testmiljö, och en flytt senare är svårare än att börja rätt.*
2. **Vem betalar och befintliga användare:** ska Tacticsboard säljas som en prenumeration per person? Och vad gäller för dagens användare och för ledare i TeamZone-lag: gratis tills vidare, eller betalt som alla andra?
3. **Pris:** vilket månadspris (inklusive moms) och ska det finnas ett årspris vid lanseringen?
4. **Provperiod:** hur lång, och ska kortet anges i början (Stripe drar automatiskt när provperioden är slut) eller först när den är slut?
5. **Utan betalning:** godkänner du läsläget enligt förslaget i avsnitt 3, där delade länkar fortsätter att fungera och inget raderas?
6. **Namn och adress:** vad ska produkten heta utåt ("Tacticsboard" eller "TeamZone Tacticsboard"), och på vilken adress ska den ligga, till exempel `tacticsboard.teamzoneapp.se` eller en egen domän?
7. **Bolaget:** vilket bolag säljer, med vilket organisationsnummer, momsregistreringsnummer och vilken adress? Finns ett Stripe-konto?
8. **Moms och länder:** bara Sverige vid lanseringen, eller hela EU med Stripe Tax och OSS?
9. **Biblioteket:** får betalande användare utanför TeamZone publicera till hela biblioteket från start? Om ja behövs ett sätt att anmäla innehåll.
10. **Support:** vilken adress ska användas, och hur snabbt lovar du svar?
11. **Skydd vid registrering:** ska CAPTCHA slås på i Supabase för nya konton?
