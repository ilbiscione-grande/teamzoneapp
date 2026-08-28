# FND-02 – gemensamt async-, stale-, offline- och resynckontrakt

**Datum:** 2026-08-23  
**Status:** VERIFIERAD  
**Arbetskort:** `docs/implementation/core_app_delivery_cards.md` – FND-02

## Resultat

Ett gemensamt klientkontrakt har införts för:

- initial loading;
- ready och explicit empty;
- refresh med bevarad tidigare data;
- stale data efter misslyckad refresh;
- online, reconnecting och offline;
- säkert fel utan lagrad eller exponerad backendtext;
- generation-/scopebaserad annullering av gamla asyncresultat;
- deterministisk resync efter Realtime-återanslutning.

Kontraktet används av de prioriterade läsytorna Trupp, Kalender, Inbox och Overview.

## Implementation

- `lib/src/shared/async/async_data_controller.dart`
  - `AsyncDataPhase` för loading/ready/empty/failed.
  - `AppConnectionStatus` för online/reconnecting/offline.
  - `AsyncDataController<T>` med timeout, stale fallback, refresh och scope-generation.
  - Gamla resultat ignoreras efter klubb-/lag-/routebyte eller dispose.
- `lib/src/shared/async/mutation_policy.dart`
  - Explicit policy för sign-in, roster, event, attendance, message send och upload.
  - Befintliga kommandon köas aldrig tyst; de blockeras eller kräver explicit, idempotent retry.
- `lib/src/features/calendar/calendar_services.dart`
  - Realtime subscribe-status rapporteras för subscribed, channel error, closed och timeout.
  - Ingen rå Realtime-error förs vidare till UI.
- `lib/src/features/calendar/calendar_surface.dart`
  - Reconnecting/offline markeras och tidigare data visas som stale.
  - Återanslutning utlöser full kalenderresync.
  - Byte av valda kontexter startar en ny scopead subscription och load-generation.
- `lib/src/features/roster/roster_surface.dart`
- `lib/src/features/messaging/inbox_surface.dart`
- `lib/src/features/overview/overview_surface.dart`
  - Gemensam controller, safe retry och context-race-skydd.

## Tester

- `test/fnd02_async_data_controller_test.dart`
  - loading/empty/ready;
  - gammalt contextresultat ignoreras;
  - refreshfel bevarar stale data;
  - offline→online gör exakt resync;
  - ingen befintlig mutation köas tyst.
- `test/fnd02_surface_contract_test.dart`
  - alla fyra prioriterade ytor använder kontraktet;
  - kalendern hanterar samtliga Realtime-statusar;
  - shared state lagrar inte backend-errorobjekt.

## Verifiering

- `flutter analyze`: **No issues found**.
- `flutter test --no-pub -r expanded`: **80/80 tester passerar**.
- Tidigare auth-, roster-, calendar-, callup-, messaging-, publicerings-, billing-, economy-, board-, observability- och UX-kontrakt passerar fortsatt.

## Avgränsningar

- Ingen Supabase-live-, schema-, RLS-, Storage-, Auth- eller Edge Function-ändring.
- Realtime-förändringen gäller endast klientens lokala statusobservabilitet och resync.
- Ingen generell offline-mutationskö har införts; det skulle kräva ett separat domän- och idempotensbeslut.
- Gamla projekt/databaser, produktion, webtools och workspaces är orörda.
- Paketidentiteten är fortsatt `com.teamzone.teamzone`.

## Nästa grind

FND-03 kan bygga gemensamma formulär-, lista- och navigationsmönster ovanpå det verifierade async-kontraktet.
