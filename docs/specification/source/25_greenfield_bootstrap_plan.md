# S00 – greenfield-bootstrap i `C:\Dev\TeamzoneApp`

**Status: planerad och scopead 2026-08-07. Målmappen är tom; ingen bootstrap har körts. Separat “Kör S00”-tillstånd krävs.**

## Bindande projektgräns

| Område | Beslut |
|---|---|
| Legacy/speckälla | `C:\Dev\TeamZone` används skrivskyddat för implementationsevidens och som källa till godkända rebuilddokument |
| Ny kodbas | `C:\Dev\TeamzoneApp` blir eget greenfield-repo |
| Kodåteranvändning | Ingen kopiering av legacy `lib/`, webbimplementation, migrationshistorik eller Edge Function-kod |
| Tillåten kunskapsåteranvändning | Godkända produktbeslut, krav, domän/API-kontrakt, testvektorer och verifierad match v2-semantik |
| Data/backend | Auditprojekt används för framtida S01-tester; Teamzone6 live lämnas orört utan separat livegodkännande |
| Supabaseprojekt | Ny lokal mapp innebär inte automatiskt ett nytt Supabaseprojekt; miljötopologi beslutas separat |

Brandassets, copy och ikoner får bara kopieras efter separat inventering av rättighet, kvalitet och om de fortfarande uttrycker målprodukten. Credentials, `.env`, signingfiler, service-/secret keys, `.temp` och genererade buildfiler får aldrig kopieras.

## Verifierad baseline 2026-08-07

- `C:\Dev\TeamzoneApp` finns och är tom; ingen `.git` finns.
- Tool paths hittades för Flutter/Dart, Java 17, Node/npm, Supabase CLI och Git.
- Tidigare miljöaudit verifierade Flutter 3.44.8, Dart 3.12.2, Java 17, Android SDK 36, Node 24 LTS och Supabase CLI 2.111.0.
- Ett samlat `flutter --version`-kommando timeoutade i denna kontroll; S00 kör separata health checks och diagnostiserar eventuell startup/blockering innan scaffold.
- Nuvarande legacyidentiteter är `com.teamzone.teamzone` för Android/iOS. De återanvänds inte automatiskt utan verifiering av store-/signingägarskap.
- Windowsmaskinen kan utveckla Android/webb och skapa iOS-projektfiler, men iOS build/signering kräver senare macOS-/CI-miljö.
- Docker/Podman/lokal PostgreSQL är inte ett S00-krav. Auditprojektet förblir hosted migrations-/JWT-testmiljö.

## Beslut som krävs före slutlig scaffold

| ID | Fråga | Rekommenderad standard | Grind |
|---|---|---|---|
| S00-DEC-01 | Dartprojektnamn | `teamzone_app` | Före `flutter create` |
| S00-DEC-02 | Android application ID/iOS bundle ID | Behåll `com.teamzone.teamzone` endast om rebuilden ska uppdatera befintlig store-app och signingåtkomst verifieras | Före signerad klientrelease; kan scaffoldas med beslutat ID |
| S00-DEC-03 | Visningsnamn | `TeamZone` | Före första UI-build |
| S00-DEC-04 | Ny Git remote/reponamn | Eget repo, exempelvis `teamzone-app`; remote skapas/pushas endast efter uttryckligt godkännande | Före första push |
| S00-DEC-05 | Backendmiljöer | `audit`, senare `staging`, och explicit `production`; ingen hemlig nyckel i klient | Före Supabasekoppling |

Om produktägaren inte ändrar DEC-01/03 används rekommendationerna. DEC-02, DEC-04 och faktisk backendtopologi får inte antas genom bootstrapen.

## S00-tasklista

| Status | Task | Leverans/acceptans |
|---|---|---|
| [ ] | S00-ENV-01 | Kör separata `flutter/dart/java/node/npm/supabase/git`-versioner och spara sanerad baseline |
| [ ] | S00-ENV-02 | Kör `flutter doctor -v`; klassificera blockers för Android, web och framtida iOS utan att installera onödiga komponenter |
| [ ] | S00-ENV-03 | Verifiera Android SDK/licenser, Java 17 och minst emulator/fysisk enhet; trådlös ADB är valfri |
| [ ] | S00-ENV-04 | Konfigurera endast det som health checks visar saknas; admin-/systeminstallation kräver separat godkännande |
| [ ] | S00-FS-01 | Återverifiera att `C:\Dev\TeamzoneApp` är tom och initiera eget Git-repo utan remote |
| [ ] | S00-FLT-01 | Skapa Flutterprojekt från grunden för Android, iOS och web; inga Windows/macOS/Linux desktop targets i v1 |
| [ ] | S00-FLT-02 | Lås Flutter/Dartkompatibilitet, dependencies och `pubspec.lock`; inga opinnade git/path-dependencies |
| [ ] | S00-ARCH-01 | Skapa minimal struktur för app/core/features/shared/test utan legacykod och utan förtida domänimplementation |
| [ ] | S00-CONF-01 | Lägg till miljökontrakt och `.env.example`/dart-define-dokumentation med placeholders; inga verkliga keys |
| [ ] | S00-SUPA-01 | Initiera lokal `supabase/`-struktur/config vid behov, men länka eller skriv inte till liveprojekt |
| [ ] | S00-DOC-01 | Kopiera endast godkända rebuilddokument 00–25 till en versionsmärkt referenssnapshot med källpath/datum/hash |
| [ ] | S00-QA-01 | Aktivera lints, format, unit/widget smoke, secret scan och analys; grundprojektet ska vara rent |
| [ ] | S00-CI-01 | Förbered lokal/CI-kommandomatris för analyze/test/web build/Android debug; remote workflow aktiveras först när repo/remote beslutats |
| [ ] | S00-SEC-01 | Verifiera `.gitignore` för env, signing, Supabase temp, IDE/build och testcredentials |
| [ ] | S00-EVID-01 | Skapa S00-evidensrapport med versionsbaseline, filer, tester, avvikelser och rollback (ta bort endast den nya tomma/scaffoldade mappen före användardata) |

## Avsiktligt utanför S00

- Inga mål-databastabeller, RLS-policies, RPC:er eller migrationsbackfills.
- Ingen koppling till Teamzone6 live.
- Ingen Auth-/Supabaseklient med verkliga URL:er/keys.
- Ingen S01 identity-, context- eller navigationimplementation utöver Flutterstandardens smokegrund.
- Ingen GitHubremote, push, PR, appstorekonfiguration eller signing.
- Ingen import av legacykod eller gamla paket “för säkerhets skull”.

## S00-exitgrind

S00 är klart först när:

1. den nya mappen är ett självständigt, rent Git-/Flutterprojekt;
2. Android- och webbgrund kan analyseras/testas/buildas enligt miljön;
3. iOS-projektfiler finns men plattformsbegränsningen är dokumenterad;
4. inga secrets eller legacyimplementationer finns i repot;
5. specifikationssnapshoten är spårbar till `C:\Dev\TeamZone`;
6. rollback och alla miljöavvikelser är dokumenterade;
7. S01 fortfarande är avstängd tills separat implementationstillstånd ges.

