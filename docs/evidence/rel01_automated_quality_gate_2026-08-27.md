# REL-01 – automatiserad kvalitetsgrind (2026-08-27)

## Resultat

REL-01 är implementerad som `tool/release_quality_gate.ps1`. Grinden kör nio namngivna steg sekventiellt, ger varje steg en egen timeout, sparar stdout/stderr separat och skriver en maskinläsbar JSON-rapport under den git-ignorerade katalogen `docs/evidence/local/`.

Grinden innehåller inga deploy-, Supabase-push-, produktionsprovisionerings-, webtools- eller workspacekommandon.

## Första fulla körningen

Rapport: `docs/evidence/local/rel01_quality_gate_latest.json` (lokal, git-ignorerad).

| Steg | Resultat |
|---|---|
| Dart format | timeout före output |
| Flutter analyze | timeout i den samlade körningen |
| Flutter test | timeout före output |
| Flutter web build | timeout före output |
| Flutter debug APK | timeout före output |
| Publiksajtstest | `spawn EPERM` |
| Publiksajt typecheck | godkänd |
| Publiksajt build | kompilering/TypeScript godkänd, därefter `spawn EPERM` |
| Säkerhetskontrakt | timeout före Flutter-testoutput |

Timeoutshanteringen korrigerades därefter för att avsluta hela Windows-processträdet och fortsätta rapporteringen. En femsekunders smoke nådde samtliga nio steg och skrev komplett rapport.

## Separat analys

Det tidigare dubblerade `Annat`-fältet i den konstanta översättningsmappen rättades. En separat `flutter analyze` slutfördes därefter och rapporterade inga analysfel i produktkoden, men 16 `curly_braces_in_flow_control_structures`-anmärkningar i tidigare Inbox/Hem-filer gör fortfarande exit status 1. REL-01:s eget kontraktstest analyseras utan anmärkning.

## Återstående grind

- rätta eller uttryckligen besluta om de 16 klammer-linterna;
- få Dart/Flutter-runner och byggkommandon att avsluta reproducerbart;
- köra full Flutter-svit samt web-/APK-build;
- köra publiksajtstest och Next-build i miljö som tillåter child-processer;
- köra säkerhetskontrakten och granska loggredaction/ACL/RLS-resultatet.

REL-01 står därför som `[~]`, inte godkänd. Ingen live- eller produktionsmiljö ändrades.

## Uppföljning 2026-08-28

De 16 mekaniska `curly_braces_in_flow_control_structures`-anmärkningarna rättades manuellt i Inbox- och Hem-koden utan beteendeförändring. REL-01-kontraktstestets två interpoleringsfel rättades och dess riktade analys passerar utan anmärkning.

Node-stegen kördes därefter utanför sandboxens child-processbegränsning:

- publiksajtstest: 22/22 godkända;
- publiksajtens TypeScript-kontroll: godkänd sedan föregående körning;
- full Next 16.3.1-produktionsbuild: godkänd, inklusive TypeScript, tre page-data-workers och fem statiska sidor.

`flutter analyze` startades också utanför sandboxen men hängde efter `Analyzing TeamzoneApp...` utan slutresultat och avbröts efter mer än två minuter. Flutter-format, analys, full testsvit och båda Flutter-byggena kvarstår därför som öppna miljögrindar.

En skrivskyddad `flutter doctor -v` verifierade Flutter stable 3.44.8, Dart 3.12.2 och SDK-sökvägen `C:\Dev\FlutterSDK` på några sekunder, men hängde därefter innan nästa toolchainsektion kunde rapporteras. Det stärker bedömningen att kvarvarande REL-01-blockering finns i lokal toolchain-/underprocessinitiering snarare än i publiksajten.

## Slutlig verifiering 2026-08-28

Blockeringen isolerades till Flutter-wrapperns åtkomst till SDK-cachelåset. Kvalitetsgrinden använder därför den installerade Dart-binären och `flutter_tools.snapshot` direkt, med samma timeout-, logg- och rapportkontrakt som tidigare.

- Dart-format: 125 filer, 0 ändringar.
- Dart-analys: inga anmärkningar.
- Flutter: 256/256 tester godkända.
- Flutter web: godkänt, `build/web` skapad.
- Android debug: godkänt, `build/app/outputs/flutter-apk/app-debug.apk` skapad.
- Publiksajt: 22/22 tester, lint/typecheck och Next-produktionsbuild sedan tidigare godkända.
- Säkerhetskontrakt: ingår i den gröna fulla Flutter-sviten.

Verifieringen rättade samtidigt mobil layout för kalenderkontroller, 200-procentig textskalning i Assistant Coach-panelen, fail-safe rollprojektioner, textkontrollers livscykel vid trupparkivering samt svensk/engelsk copy-gräns. Inga live- eller produktionsmiljöer ändrades.

## Routingregression 2026-08-30

Efter webbens canonical path-, Overlay- och detalj-URL-rättningar kördes hela grinden på nytt mot slutlig filstatus. Fem tidigare testfiler formaterades mekaniskt; därefter passerade formatkontrollen med 148 filer och 0 ändringar.

- REL-01: `passed`, 9/9 steg.
- Dart-analys: inga anmärkningar.
- Flutter: 321/321 tester godkända.
- Flutter web och Android debug APK: godkända.
- Publiksajt: 22/22 tester, typecheck och komplett Next-build godkända.
- Säkerhetskontrakt: 20/20 i det separata grindsteget, utöver fullsviten.

Den maskinläsbara rapporten finns lokalt i `docs/evidence/local/rel01_quality_gate_latest.json`. Ingen Supabase-liveändring, produktionsprovisionering, webtools eller workspaces utfördes.

## Regression efter veckans merge 2026-09-04

Mellan 2026-08-28 och 2026-09-04 samlades en veckas arbete (TEAM-05–08, CAL-10,
PUB-03–06, MSG-01–08-förbättringar, hela AC-04–08 samt routing-utbrytningen)
ocommitterat i arbetsträdet. Grinden hade inte kunnat köra klart under den
tiden, så den fulla testsviten hade aldrig körts mot den sammanslagna koden
förrän nu. Arbetet säkrades i git (`c0454e4`, `6ad57d2`) innan grinden kördes
om i sin helhet med samma direkta Dart-anrop som den slutliga verifieringen
2026-08-28.

Första körningen efter merge:

- Dart-format: 8 filer skulle formaterats om (`--output=none` skrev inget till disk).
- Flutter: **322/349 godkända, 27 fallerande**.
- Flutter web och Android debug APK: godkända, opåverkade av testfynden.

Samtliga 27 fel spårades till sex distinkta, dokumenterade orsaker i stället
för 27 separata buggar:

1. **Kontextetikett (21 fall)** – `product_shell.dart` visar sedan AC-07
   avsiktligt `"lag · roll"` i huvudkontextväljaren i stället för bara
   lagnamnet. Äldre tester i `app_smoke_test`, `auth02_session_context_test`,
   `fnd01_fnd03_verification_test`, `fnd05_accessibility_localization_test`
   och `rel02_automated_release_matrix_test` sökte exakt lagnamn. På
   tablet/desktop visar dessutom Min assistents integrerade sidopanel samma
   kontext parallellt med appfältet (två separata, avsiktliga träffar), så
   `findsOneWidget` byttes till `findsWidgets` samtidigt som sökningen
   byttes till `find.textContaining(...)`.
2. **Ikonknapp i stället för textknapp (1 fall)** – `team05`: lagkoders
   "Återkalla" renderas som en `IconButton` med tooltip sedan "Visa kod"
   lades till bredvid, konsekvent med samma mönster som redan användes för
   "Visa kod" i samma test. Testet uppdaterades till `find.byTooltip(...)`.
3. **Omdöpt lokal variabel i migration (2 fall)** – `home03` och `msg02`
   kontrollerade exakt SQL-text mot lokala variabler som avsiktligt döptes
   om (`guardian_person_id` → `guardian_actor_person_id`,
   `thread_id` → `function_body.thread_id`) för att lösa en tvetydig
   kolumnreferens. De förväntade substrängarna uppdaterades i testerna.
4. **Verklig saknad översättning (1 fall)** – `roster_surface.dart` anropar
   `.feature('Inbjudningskoden har kopierats.')`, men strängen saknades i
   `_featureEnglish`-tabellen i `app_strings.dart` och hade kastat
   `StateError` i engelskt körläge. Översättningen lades till.
5. **Knapp utanför testytan (1 fall)** – `team04`: "Spara person" kunde
   hamna under vikningen på standardtestytan (800×600); testet saknade det
   `tester.ensureVisible(...)`-anrop som redan användes för samma flödes
   skapa-väg i samma fil. Anropet lades till före tap.
6. **Testuppsättning utan locale-delegates (1 fall)** – `team05`: ett
   fristående `MaterialApp` i lokaliseringstestet saknade
   `supportedLocales`/`localizationsDelegates`, så `Locale('sv')` föll
   tillbaka till engelska. Uppsättningen justerades till samma mönster som
   `context_selector_role_label_test.dart` redan använder.

Efter fix 1–6 kördes sviten om: 14 kvarvarande fall, samtliga
tablet/desktop-varianter av orsak 1 (två legitima träffar, `findsOneWidget`
för strikt). Efter att `findsOneWidget` byttes till `findsWidgets` för de
fem berörda assertionerna:

- Dart-format: 150 filer, 0 ändringar.
- Dart-analys: inga anmärkningar (35,4 s).
- Flutter: **349/349 godkända**.

Endast testfiler och en översättningstabellrad (`app_strings.dart`)
ändrades; ingen produkt-/domänlogik rördes. Flutter web och Android debug
APK verifierades tidigare i samma session och byggdes inte om efter de sista
testfixarna eftersom endast testfiler och en konstant strängtabell
ändrats.

Publiksajtens npm-steg kördes därefter om mot veckans PUB-04-mediaworker/
proxyändringar:

- `npm test`: 26/26 godkända.
- `npm run lint` (`tsc --noEmit`): inga fel.
- `npm run build` (Next.js 16.3.1, Turbopack): godkänt, inklusive den nya
  `/media/public/[token]`-routen, `/api/public/v1/*`, proxy-middleware och
  statiska `robots.txt`/`sitemap.xml`.

**REL-01 är därmed grön i samtliga nio steg mot den aktuella sammanslagna
koden.** Ingen Supabase-liveändring, produktionsprovisionering, webtools
eller workspaces utfördes.
