# Tacticsboard i produktionen (punkt 15)

Checklista för att lansera Tacticsboard i produktionsprojektet
`zfxcblgnemuenaqjkaic` (eu-north-1). Läget kontrollerades 2026-11-04 med
`config diff`, `migration list`, `functions list`, `secrets list` (bara namn)
och läsfrågor i databasen. Faserna i
`docs/operations/production_provisioning.md` och hemligheterna i
`docs/operations/production_secrets.md` gäller fortfarande. Den här listan
tar bara det som Tacticsboard behöver.

**Vem gör vad:** du gör det som kräver inloggning, konton, nycklar eller
betalning. Jag kör migrationer och driftsättningar när du säger ja, och
kontrollerar varje steg.

## Läget 2026-11-04

| Del | Läge |
|---|---|
| Migrationer | Alla 435 körda. De fem sista kördes 2026-11-04: tabellerna har RLS, 44 funktioner är spärrade som i test, prislistan är tom tills steg 9 |
| Edge-funktioner | Alla 18 driftsatta. `tacticsboard-billing`, `account-deletion` och `stripe-webhook` kom 2026-11-04. Webhooken svarar `billing_unavailable` tills Stripe-nycklarna finns |
| Edge-hemligheter | 13 namn. Saknas: `RESEND_API_KEY`, `SUPPORT_EMAIL_FROM`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SIGNING_SECRET` |
| Vault | Alla sex namn finns |
| Villkor | `terms` och `privacy` version 2026-08-24 är aktiva, som i test |
| Konton | 0 användare, 0 supportkonton |
| Webtools | Har ingen produktionsbackend. `teamzoneapp-webtools` pekar på testprojektet |

## Fel i produktionens inställningar

1. **Data API exponerar fel scheman.** Produktionen har `public` och
   `graphql_public`, men alla klienter anropar `api`. Utan ändringen fungerar
   ingenting. Ändra under Project Settings → Data API: Exposed schemas bara
   `api`, och Extra search path bara `extensions`. Det är så det står i
   `supabase/config.toml`.
2. **Site URL är `http://app.teamzoneapp.se`.** Den ska vara
   `https://app.teamzoneapp.se`. Ändra under Authentication → URL
   Configuration.
3. **Omdirigeringarna saknar appens adress.** Lägg till
   `teamzone://app/auth/callback`. `https://app.teamzoneapp.se/auth/callback`
   och `https://webtools.teamzoneapp.se/logga-in**` finns redan.

Kontrollerat igen 2026-11-04: Exposed schemas, Extra search path, Site URL och
omdirigeringarna är rättade.

Lösenordsreglerna (8 tecken, alla teckentyper), e-postbekräftelsen och
TOTP stämmer redan.

## Steg

| # | Steg | Vem | Klart |
|---|---|---|---|
| 1 | Organisationen på Pro, tvåfaktorsinloggning krävs, Supabases DPA godkänt, skydd mot läckta lösenord på (Authentication → Providers → Email) | Du | |
| 2 | Rätta inställningarna ovan: Extra search path till bara `extensions`, och Site URL till `https://webtools.teamzoneapp.se` (se Beslut) | Du | Klart 2026-11-04 |
| 3 | SMTP via Resend med en egen nyckel för produktionen: smtp.resend.com, port 465, användaren `resend`, avsändaren `noreply@teamzoneapp.se` med namnet "TeamZone". Samma nyckel som `RESEND_API_KEY`, och `SUPPORT_EMAIL_FROM` = `TeamZone <support@teamzoneapp.se>` | Du | |
| 4 | Svenska mejlmallar i `supabase/templates/`, att klistra in under Authentication → Emails, i test och produktion. Ämnesrader: Confirm signup "Bekräfta din e-postadress", Magic link "Din kod för att logga in", Reset password "Välj ett nytt lösenord", Change email "Bekräfta din nya e-postadress". Appen loggar in med kod, så de två första visar både länk och kod. Mallarna är inte provade i en riktig inkorg | Du klistrar in | |
| 5 | De fem migrationerna: `npx supabase db push --remote=zfxcblgnemuenaqjkaic --skip-vault`, sedan `migration list` och kontroll av tabeller, RLS och spärren (44 spärrade funktioner) | Jag, efter ditt ja | Klart 2026-11-04 |
| 6 | Stripe i skarpt läge: kontot aktiverat, produkten Tacticsboard med 79 kr/mån och 790 kr/år inklusive moms, kupongen `LANSERING50` (50 %, en gång, går att lösa in till och med 2026-12-31), Stripe Tax för Sverige, Customer Portal som i test. Public details är gemensamma för test och skarpt läge och är redan ifyllda | Du | |
| 7 | Webhooken i skarpt läge till `https://zfxcblgnemuenaqjkaic.supabase.co/functions/v1/stripe-webhook` med `checkout.session.completed` och `customer.subscription.created`, `.updated` och `.deleted`, plus de händelser som klubbarnas betalning redan använder | Du | |
| 8 | Hemligheterna `STRIPE_SECRET_KEY` (en begränsad nyckel räcker) och `STRIPE_WEBHOOK_SIGNING_SECRET` | Du | |
| 9 | Raderna i `internal.personal_billing_prices` med de skarpa pris- och kupong-id:na | Jag skriver SQL, du ger id:na (de är inte hemliga) | |
| 10 | Driftsätt `tacticsboard-billing`, `account-deletion` och `stripe-webhook`. Obs: funktionerna byggs från arbetskopian, så andras ocommittade ändringar i `_shared` följer med. Kontrollera diffen först | Jag, efter ditt ja | Klart 2026-11-04 |
| 11 | Webtools i produktionen: en ny App Hosting-backend `teamzoneapp-webtools-prod` (rot `/webtools`, miljön `production`) och en `webtools/apphosting.production.yaml` med produktionens `SUPABASE_URL`, den publicerbara nyckeln och en egen secret för `SUPABASE_SECRET_KEY` | Filen är skriven. Du skapar backend och secreten `teamzoneapp-production-webtools-supabase-secret-key` | Backend, miljönamn och secret klara 2026-11-04. Driftsättning kvar |
| 12 | Domänen `webtools.teamzoneapp.se` till produktionsbackenden (DNS i Netlify). Adressen visar i dag den gamla sajten, som ersätts. Testets Webtools ligger kvar på hosted.app-adressen | Du | |
| 13 | Ditt konto som support: en rad i `internal.support_admins` när du har registrerat dig i produktionen | Jag skriver SQL | |
| 14 | Nya versioner av villkoren i `internal.legal_document_versions` när texterna är granskade, i test och produktion | Jag, efter punkt 11 | |
| 15 | Provet i produktionen: registrering, provperiod, ett riktigt köp av månaden, sedan återbetalning och uppsägning i Stripe | Du köper, jag kontrollerar | |
| 16 | Firebase-hemligheten `TEAMZONE_PRODUCTION_SUPABASE_ANON_KEY` med produktionens publicerbara nyckel. Edge-hemligheterna `OBSERVABILITY_BRIDGE_URL` = `https://europe-west1-teamzoneapp-b02a2.cloudfunctions.net/criticalFlowAlertBridge` och `OBSERVABILITY_BRIDGE_TOKEN`, samma värde som Firebase-hemligheten `TEAMZONE_OBSERVABILITY_BRIDGE_TOKEN`, eftersom båda miljöerna larmar till samma brygga | Du | |
| 17 | `TEAMZONE_PRODUCTION_SUPABASE_URL` i `firebase-functions/.env.teamzoneapp-b02a2` (filen är inte versionshanterad), sedan `deploy --only functions`. Görs efter steg 16, annars misslyckas driftsättningen. Kontrollera att `runProductionCriticalFlowMonitor` svarar utan fel | Jag, efter ditt ja | |

## Beslut (2026-11-04)

- **Site URL:** `https://webtools.teamzoneapp.se` i produktionen, eftersom
  bara Tacticsboard finns där vid lanseringen. `app.teamzoneapp.se` är i dag
  testets Flutter-app. Site URL är bara reservadressen, och Webtools skickar
  alltid en egen adress. Byt tillbaka när fas 4 flyttar appen.
- **Den publika sajten** ligger kvar på testbackenden vid lanseringen.
  `public-site/proxy.ts` slår upp varje adress i databasen och ger 404 om
  uppslaget misslyckas. Under testprojektets avbrott 2026-11-04 svarade därför
  hela sajten 404, även villkoren som Stripe Checkout länkar till. Nu hoppar
  `/villkor`, `/villkor/tacticsboard` och `/integritet` på
  `teamzoneapp.se` över uppslaget (`isCanonicalLegalPage`). Resten av sajten
  beror fortfarande på testprojektet, tills fas 4.3 flyttar den.
- **Övervakning:** produktionen bevakas från lanseringen, steg 16 och 17.
- **Länken till TeamZone-appen.** Sidfoten i Webtools länkar till
  `app.teamzoneapp.se`, som är testappen, så en betalande kund kan hamna där.
