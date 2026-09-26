# PUB-02 – förberedelse för riktig webbvisning

Status: de två PUB-02-rättningarna är tillämpade och testprojektets publika
runtime aktiverades efter separat uttryckligt godkännande. Lokal verklig
klubb-/lagvisning är verifierad. Tidigare förberedelsesteg nedan är historik.

Produktägaren vill se Thomas klubbs och Thomas lags riktiga publika sidor
innan lagledaransökan testas. Valet var ”Förbered riktig webbvisning”.
Detta är inte ett godkännande att aktivera global publik runtime.

## Skrivskyddat bekräftat i hgcshgunvooyudvrcpig

- Thomas klubb: `published`, revision 3, aktiv giltig bekräftelse,
  adress `/thomas-klubb-6379829a`, valda fält name/locality/description.
- Thomas lag: `published`, revision 3, aktiv giltig bekräftelse,
  adress `/thomas-klubb-6379829a/thomas-lag`, valda fält name/age_class.
- Noll klubbprojektioner och noll lagprojektioner.
- Sju väntande projektionsjobb: fyra rebuild och tre remove.
- Runtime är false och constraint `publication_runtime_state_enabled_check`
  kräver att den förblir false. Ingen aktiveringsändring har gjorts.
- `cron.job` finns inte; någon databasbaserad schemalagd worker har därför
  inte kunnat konstateras. Externa schedulers är inte inventerade.

## Lokal webb

Grundappen finns på localhost:5000. Befintlig Next.js-webb startades på
localhost:5001 med `TEAMZONE_LOCAL_PUBLIC_VIEW=1` i developmentläge, bunden
till IPv6 loopback. Endast de exakta loopbackvärdarna med port 5001 får
lokal routning, no-store och noindex. Vanliga databas-RPC:er, allowlists,
rate limits och runtimespärr används fortfarande; inga exempeldata eller
privata tabelläsningar har lagts till i webbappen.

31/31 Node-tester passerar och `npm run lint` (TypeScript) passerar.
HTTP-kontroll av klubbadressen gav 200 och `X-Robots-Tag: noindex, nofollow`.
Next.js developmentserver satte slutlig Cache-Control till
`must-revalidate, no-cache` trots proxyns no-store. Svaret verifierar endast
att routen renderas; det verifierar inte att klubbdata visas.
Serverkonfigurationen saknar fortfarande databasens servernyckel samt
lokal PUBLIC_ORIGIN/IP-HMAC-konfiguration. Nyckeln ska enbart användas av
serverprocessen och får aldrig hamna i browserkod, logg eller versionshantering.

Automatisk säkerhetsgranskning avvisade CLI-hämtning av fullständiga befintliga
projekt-API-nycklar, eftersom den känsliga credentialåtkomsten inte uttryckligen
godkänts. Hämtningen genomfördes inte. Den ska inte kringgås med en annan väg.

## Förberedd rättning av kön

`20260925175025_pub02_projection_reconciliation.sql` är skapad lokalt men
inte tillämpad. Den behåller behörigheter, allowlists och samtyckeskontroller
och ändrar två delar:

1. Beroende lagjobb köas om även när ett tidigare jobb med samma lagrevision
   finns. Nuvarande `on conflict ... do nothing` tappar återpubliceringen
   efter klubbens privat/publicerad-växling.
2. Arbetaren utgår från nuvarande inställningar och giltiga bekräftelser,
   så att gamla remove/rebuild-jobb inte skriver över ett senare beslut.
   Endast published lag under published klubb byggs som lagsida.

`supabase/tests/pub02_projection_reconciliation_rollback.sql` innehåller
ett förberett transaktionstest med rollback för sena borttagningsjobb,
privat klubb, återpublicering och stängd anon/runtime-gräns. Det är inte
kört. Runtime-, syntax- och privilegieverifiering i testprojektet återstår.
Detta kräver separat godkännande för den nya testprojektsskrivningen.

## Nästa avgränsade godkännande

- Läs testprojektets befintliga servernyckel till lokal serverkonfiguration
  utan utskrift, klientexponering eller nyckelrotation.
- Kör den förberedda nya migrationen och testet i en rollback-transaktion
  i exakt `hgcshgunvooyudvrcpig`; redovisa resultat och verifiera att
  ursprungligt läge och avstängd runtime är återställda.
- Efter godkända tester kan permanent rättning och workerdrift förberedas.

Global runtimeaktivering ska vara ett separat senare beslut. Befintlig
App Hosting-konfiguration pekar på samma testprojekt; en global aktivering
kan därför påverka externa webbmiljöer trots att inget nytt driftsätts.
Aktivering får inte ske förrän projektionernas avpublicering, återpublicering
och cachehantering fungerar och den faktiska externa räckvidden är klarlagd.
Ingen separat produktion, gamla TeamZone-projektet eller gamla databaser ingår.

## Godkänt och genomfört förberedelsesteg 2026-09-25

Produktägaren svarade ”ja” på separat fråga om hämtning av befintlig
servernyckel och databasprov med full rollback. Den godkända nyckelhämtningen
genomfördes utan nyckelutskrift. Serverns nyckel, testprojektets URL,
slumpad IP-HMAC-hemlighet, lokal origin och proxyinställning finns nu i
`public-site/.env.local`; `git check-ignore` bekräftar att filen ignoreras.
Befintlig CAPTCHA-konfiguration bevarades. Ingen nyckel roterades.

Direkt läsning med lokal serverkonfiguration verifierade `connected=true`
och `runtimeBlocked=true`. Klubb- och lagrouten svarar lokalt med HTTP 200
och noindex. Dessa svar är fortfarande inaktiva sidor, inte innehållsbevis.

Den nya migrationen och rollback-testet kördes tillsammans i en transaktion
via SQL-anslutningen till exakt `hgcshgunvooyudvrcpig`, utan migrationsbokföring.
Testet utökades för att även köra publiceringskommandot som tidigare ansvarig
användare och kontrollera omköning av slutförda lagjobb vid klubbens
av-/återpublicering. Båda körningarna passerade och avslutades med rollback.

Verifierat i rollback-testet:

- Sena remove-jobb återskapar nuvarande giltigt publicerat klubb-/lagläge.
- Privat klubb tar bort klubb- och lagprojektionerna.
- Återpublicerad klubb kan återfå lagprojektionen.
- Avpubliceringskommandot köar om det slutförda remove-jobbet för laget.
- Återpubliceringskommandot köar om det slutförda rebuild-jobbet för samma lagrevision.
- Anon kan inte köra projektionsarbetaren och runtime förblir false.

Efterföljande skrivskyddad kontroll matchade före-testets MD5-fingeravtryck
för hela klubbinställningar, laginställningar, jobb, bekräftelser och de två
funktionsdefinitionerna. Båda projektionstabellerna är åter tomma och runtime
är false. Rättningen finns alltså fortfarande endast lokalt.

Detta steg godkänner inte permanent migration, behandling av kön utan rollback,
extern driftsättning eller global runtimeaktivering. Kontroller av samtidig
workerdrift, extern räckvidd och cacheinvalidering återstår inför aktivering.

## Färdigställd lokal jobb-/cachekedja 2026-09-25

Efter ”kör” och ”fortsätt” förbereddes ytterligare migration
`20260925175933_pub02_publication_worker_delivery.sql`. Den är inte permanent
tillämpad. Den gör claim och projektion i en gemensam transaktion, behandlar
klubbar före lag och använder ett transaktionslås för samtidiga batchanrop.
Cacheclaim omfattar även rebuild/remove-jobb som väntar på invalidering.
Varje claim får en unik token; en gammal worker kan inte kvittera ett
återtaget jobb. Avbrutna cacheclaims kan återtas efter tio minuter.

Next.js-routen för cacheinvalidering kör nu projektion, claim, revalidatePath
och tokenbunden kvittens i ordning. Fel lämnar retrybart jobb eller utgången
claim för återtagning. Saknade eller otillåtna paths blir fel, inte lyckad
invalidering. Obehörigt HTTP-anrop verifierades ge 404.

37/37 webbtester och TypeScript-kontrollen passerar. Utökat rollback-test i
testprojektet passerar för atomisk batch, dubbla claims, fel token, återtagen
claim, fördröjd kvittens, cachefel och klienternas nekade workeråtkomst.
Detta verifierar SQL-protokollet, inte en distribuerad last-/CDN-mätning.
Efter rollback matchar tidigare fingeravtryck, nya funktioner/kolumnen saknas,
runtime är false och klubb/lag/event/nyhet/partnerprojektioner är tomma.

Lokal driver `public-site/scripts/local-publication-worker.mjs` är förberedd
för --once eller --watch (10 sekunder mellan körningar). Endast --check har
körts. Den begränsas till localhost:5001 och godkänt testprojekt, använder en
slumpad serverhemlighet från git-ignorerad .env.local och skriver inga nycklar.
Ingen schemalagd extern worker eller produktion har startats.

Extern HTTP-kontroll bekräftar:

- `https://public.teamzoneapp.se/thomas-klubb-6379829a`: HTTP 200 och inaktiv sida.
- `https://teamzoneapp.se/thomas-klubb-6379829a`: HTTP 200, men innehållet är
  inte verifierat som samma publiceringsruntime.

## Konkret aktiveringsförslag – kräver separat godkännande

1. Tillämpa endast de två lokala PUB-02-migrationerna ovan i
   `hgcshgunvooyudvrcpig` (ingen generell push av andra lokala migrationer).
2. Starta lokal driver och behandla de väntande klubb-/lagjobben. Verifiera
   att enbart Thomas klubbs och Thomas lags uttryckligt valda fält projiceras
   och att jobben kvitteras via den lokala cache-routen.
3. Kör `ops/pub02_enable_audit_public_runtime.sql` separat. Skriptet kräver
   exakt en publik klubb och ett lag, rätt pilotadresser, aktuella revisioner,
   giltiga bekräftelser och inga ofärdiga jobb innan spärren ändras.
4. Visa och kontrollera de riktiga sidorna på localhost:5001. Den globala
   ändringen kan även göra sidorna åtkomliga på redan uppsatt extern webb,
   särskilt public.teamzoneapp.se. Ingen ny extern webbdriftsättning ingår.

`ops/pub02_disable_audit_public_runtime.sql` är förberett som manuell
avstängning: enabled=false och den strukturella false-spärren återställs.
Klubbens/lagets publiceringsval bevaras. Extern cache kan behöva löpa ut;
ingen CDN-invalidering eller mätt global avstängningstid är verifierad här.

Inga aktiverings-/avstängningsskript eller permanent workerdrift har körts.

## Godkänd aktivering och verklig webbvisning 2026-09-25

Produktägaren svarade ”ja” på den separata frågan om de två rättningarna,
publiceringsjobben och global runtimeaktivering, inklusive möjlig extern
åtkomst på public.teamzoneapp.se.

- Endast migrationerna `pub02_projection_reconciliation` och
  `pub02_publication_worker_delivery` tillämpades via MCP i testprojektet.
- Lokal worker rapporterade projected=7, claimed=7, completed=7, failed=0.
- Skrivskyddat verifierat: en klubbsida och en lagsida, båda published,
  source_revision=3; alla sju jobb completed. Klubben har official=false.
- Det förberedda aktiveringsskriptet kördes efter dessa kontroller. Runtime
  är enabled=true, revision=2, gate_version=pub02-audit-web-pilot-2026-09-25.
- Lokal driver kör i --watch-läge med tio sekunders intervall. Det är en
  lokal utvecklingsprocess, ingen extern produktionsworker. Nya publicerings-
  ändringar kräver att den lokala servern och drivern fortsätter köra.
- Båda lokala sidorna ger HTTP 200 med verkliga namn, ort/presentation
  respektive åldersklass. Browserkontroll bekräftar Thomas klubb, länk till
  Thomas lag, J18 och korrekt inofficiell märkning. Båda öppnades åt användaren.
- Båda motsvarande adresserna på public.teamzoneapp.se visar nu också
  innehåll. Extern webb är en äldre klient och har etiketten ”Verifierad
  publicering”; den lokala nya klienten visar korrekt ”Inofficiell klubb”.
  Ingen extern webbdriftsättning gjordes i detta steg.
- Security Advisor: INFO för befintliga stängda RLS-tabeller utan policy och
  den sedan tidigare kända varningen om avstängt läckt-lösenordsskydd.
  Ingen ny worker-relaterad säkerhetsvarning returnerades.
  Referenser: [RLS-info](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy),
  [lösenordsskydd](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

Kvar: användarens visuella bedömning, publik av-/återpublicering genom hela
webbkedjan, extern klientuppdatering och extern worker-/cacheverifiering.
Detta är inte en full produktionsrelease eller fullständig PUB-02-stängning.

## Extern startsida och katalog uppdaterade 2026-09-25

Produktägaren rapporterade att externa webben fortfarande visade
”Publicering är avstängd” i stället för sök. HTTP-kontroll visade att
startsidan körde äldre hårdkodad text medan externa sök-API:n redan
returnerade Thomas klubb, official=false, visibility=published.

En isolerad källkopia av aktuell public-site skapades utan .env-filer,
lokala hemligheter, tester eller utvecklingsartefakter. Next.js
produktionsbygge med webpack inklusive TypeScript passerade. Firebase CLI
driftsatte enbart backend `teamzoneapp-public` i projekt `teamzoneapp-b02a2`.
Utrullningen avslutades framgångsrikt. Grundapp, databas, DNS och andra
Firebase-resurser ändrades inte av denna webbuppdatering.

Efter driftsättning verifierades:

- Externa startsidan ger HTTP 200, visar ”Sök klubbar” och saknar den gamla
  avstängningstexten.
- Browserflödet startsida → klubbkatalog → sökning ”Thomas” hittar Thomas
  klubb med Inofficiell klubb/Vetlanda och öppnar rätt klubbsida.
- Externa klubb- och lagsidor ger HTTP 200 och visar korrekt inofficiell
  märkning. Den tidigare etiketten ”Verifierad publicering” är ersatt.
- Befintlig publik adress är fortsatt https://public.teamzoneapp.se.

Jobbdrivern kör fortfarande lokalt. Denna klientutrullning innebär inte att
en extern schemalagd worker har satts upp eller att cache-SLA har slutverifierats.
