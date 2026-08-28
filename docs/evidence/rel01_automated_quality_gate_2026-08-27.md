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
