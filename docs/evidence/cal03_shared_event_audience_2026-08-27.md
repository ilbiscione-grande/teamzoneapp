# CAL-03 – delade event och audience

Datum: 2026-08-27  
Status: lokalt genomförd, runtimegrindar återstår

## Levererat

- Primärlaget ligger kvar som eventägare och är ensamt om `manage_sharing`.
- Ett annat aktivt lag i samma klubb kan uttryckligen få `view`, `manage_roster` eller `co_manage`.
- Audience för spelare, ledare och vårdnadshavare ger läsbarhet/mottagarskap men kopplas aldrig till mutationsrätt.
- EventDetails visar ägande och deltagande lag samt en delningsdialog för behörig primärlagsledare.
- Servern validerar klubbgräns, aktivt lag, capability-lista, audience och förväntad eventrevision.
- Uppdateringen använder eventlås, advisory lock, idempotens, revision, audit och outbox.
- Trupp- och närvarohantering använder den separata roster-capabilityn i stället för generell eventåtkomst.

## Negativa gränser

- Sekundärlag kan aldrig ändra delningen.
- `view` eller audience ger ingen redigering, deltagarhantering eller transition.
- `manage_roster` ger inte eventredigering.
- `co_manage` ger inte rätt att ändra ägare eller delningskonfiguration.
- Lag utanför eventets klubb och inaktiva lag avvisas.

## Verifiering

- `flutter analyze`: godkänd, inga problem.
- Riktat kontraktstest: `test/cal03_shared_event_access_test.dart` tillagt.
- `flutter test test/cal03_shared_event_access_test.dart`: testwrappen gav ingen output och behövde avbrytas; inget testresultat kan därför hävdas.
- SQL-runtime: ej körd eftersom lokal Docker/PostgreSQL saknas och Supabase live inte får ändras utan separat godkännande.
- Fysisk flerrollsgrind: återstår för primärlagsledare, sekundärlagsledare och audience-only-användare.

## Ändrade huvudfiler

- `supabase/migrations/20260827070512_cal03_shared_event_access.sql`
- `lib/src/features/calendar/calendar_models.dart`
- `lib/src/features/calendar/calendar_services.dart`
- `lib/src/features/calendar/calendar_surface.dart`
- `test/cal03_shared_event_access_test.dart`

Ingen liveändring, produktionsprovisionering, webtool eller workspace har använts. Paketidentiteten är oförändrad.
