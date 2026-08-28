# Samlad verifiering – FND-01–FND-03

**Datum:** 2026-08-23  
**Resultat:** Godkänd automatiserad verifieringsgrind  
**Omfattning:** Lokal Flutter-klient. Ingen livebackend, webtools, workspace eller produktionsprovisionering.

## Genomförda kontroller

### FND-01

- Bootstrap, shell, router och featurefiler kompilerar utan analysfel.
- Befintliga app-, capability- och källkontrakt passerar efter extraktionen.
- Safe unconfigured, waiting room, giltig kontext och svenska/engelska bootstraplägen ingår i regressionssviten.

### FND-02

- Widgettest verifierar loading, empty, ready, stale med bevarad data och safe initial failure.
- Rå backendtext visas inte i failed/stale-vyerna.
- Befintliga controllertester verifierar context-race, offline→online-resync, refreshfel och mutationspolicy.
- Trupp, Kalender, Inbox och Overview använder samma asynckontrakt enligt ytkontraktstest.

### FND-03

- Produktens responsiva shell verifieras på:
  - phone: 390×844 med `NavigationBar`;
  - tablet: 800×1100 med `NavigationRail`;
  - desktop: 1440×900 med `NavigationRail`.
- Cold link `/team` når rätt yta och bevaras när hela appträdet byggs om, motsvarande klientrefresh.
- System-/Android-back i ett dirty formulär visar varning, kan avbrytas och kan därefter kasta ändringarna och lämna vyn.
- Form controller verifierar pending, double-submit, lyckad clean och dirty-state efter fel.
- List controller verifierar kombinerad sökning, filter, sortering, pagination och återställning.
- Routekontraktet verifierar samtliga registrerade paths, query på canonical path och säker fallback.

## Fel som upptäcktes och rättades

1. `AppUnsavedChangesScope` försökte poppa innan `PopScope` hunnit byggas om efter `markClean`. Navigationen väntar nu till nästa frame innan pop.
2. Den yttre `MaterialApp` försökte konsumera produktens cold link före den inre GoRouter-instansen. Bootstrapnavigatorn accepterar nu plattformsrutten utan att tolka den; produktens router behåller ensam routeansvaret.

## Slutresultat

- `flutter analyze`: **No issues found**.
- `flutter test`: **95/95 passerar**.
- Ny verifieringssvit: `test/fnd01_fnd03_verification_test.dart`, **6/6 passerar**.

## Fysisk Android-smoke

Verifieringen kompletterades på en ansluten Samsung SM-S931B via den uttryckligen angivna ADB-transporten `192.168.1.207:36447`:

- aktuell lokal `app-debug.apk` byggdes och installerades med bibehållet paketnamn `com.teamzone.teamzone`;
- kallstart av `com.teamzone.teamzone/.MainActivity` lyckades med rapporterad starttid 1 048 ms;
- lokal fail-closed-vy renderades korrekt i porträtt på 1080×2340, density 480;
- UI-hierarkin innehöll TeamZone, `Miljö: local` och den förväntade säkra backend-ej-ansluten-texten;
- varken Flutter- eller AndroidRuntime-fel hittades i den avgränsade logcat-kontrollen;
- fysisk system-back lämnade appens rot och återgick till föregående aktivitet.

Telefonen exponerades samtidigt via två ADB-transportnamn. Alla mutationskommandon scopeades därför explicit till IP-transporten för att undvika tvetydig enhet.

## Kvarvarande browser-smoke

Inga webtools fick startas enligt projektets avgränsning. En verklig webbläsares back/forward-knappar har därför inte körts i denna runda. Flutterkontrakten för cold link och app-rebuild är automatiskt verifierade; verklig browser-smoke återstår i en separat godkänd miljö.
