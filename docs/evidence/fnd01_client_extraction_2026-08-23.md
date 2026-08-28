# FND-01 – klientextraktion utan beteendeförändring

**Datum:** 2026-08-23  
**Status:** VERIFIERAD  
**Arbetskort:** `docs/implementation/core_app_delivery_cards.md` – FND-01

## Resultat

Den tidigare stora `lib/src/app/teamzone_app.dart` har delats upp i ytspecifika Dart-partfiler utan ändring av routes, state, datakontrakt eller användarsynligt beteende.

Appfilen äger nu bibliotekets imports/parts, `TeamZoneApp`-bootstrap och gemensamma fallbackstates. Produktskal, router och featureimplementationer ligger i egna filer men delar tills vidare samma Dart-library, vilket bevarar befintliga privata symbolgränser under den rena extraktionen.

## Extraherade gränser

- `lib/src/app/product_shell.dart`
- `lib/src/app/product_routes.dart`
- `lib/src/features/auth/auth_surfaces.dart`
- `lib/src/features/billing/billing_surface.dart`
- `lib/src/features/board/board_surface.dart`
- `lib/src/features/calendar/calendar_surface.dart`
- `lib/src/features/development/development_surface.dart`
- `lib/src/features/economy/economy_surface.dart`
- `lib/src/features/match/match_space_dialog.dart`
- `lib/src/features/messaging/inbox_surface.dart`
- `lib/src/features/overview/overview_surface.dart`
- `lib/src/features/roster/roster_surface.dart`

## Testanpassning

Tre källkontraktstester läste tidigare endast monolitfilen. De har uppdaterats till att läsa respektive featurefil tillsammans med produktens route/shell-filer:

- `test/s10_billing_surface_contract_test.dart`
- `test/s10b_economy_surface_contract_test.dart`
- `test/s10b_board_surface_contract_test.dart`

Säkerhets- och capabilityförväntningarna är oförändrade.

## Verifiering

- Riktad formatteringskontroll: 16 ändrade filer, 0 formatteringsändringar.
- `flutter analyze`: **No issues found**.
- `flutter test --no-pub -r expanded`: **72/72 tester passerar**.
- Routes och cold-linkkontrakt för billing/economy/board fortsätter testas.
- Capabilitykontrakt för billing/economy/board fortsätter testas i sina nya filgränser.

## Avgränsningar

- Ingen produktfunktion eller UX har ändrats.
- Ingen Supabase-migration, Edge Function, Storage-, Auth-, RLS- eller liveändring har gjorts.
- Gamla `C:/Dev/TeamZone` och gamla databaser har inte ändrats.
- Ingen produktion, webtool eller workspace har startats.
- Paketidentiteten är oförändrad: `com.teamzone.teamzone`.

## Nästa grind

FND-02 kan nu införa en gemensam async-, safe error-, stale-, offline- och Realtime-resynckontrakt ovanpå de separerade ytorna.
