# CAL-04 – säker eventlivscykel och radering

Datum: 2026-08-27  
Status: lokalt genomförd, runtimegrindar återstår

## Levererat

- Direkt borttagning kräver ett opublicerat, fristående draft-event på revision 1.
- Direkt borttagning blockeras av serie, delat lag, trupp, kallelse, närvaro, Match Space eller sponsorbindning.
- Endast primärlagsbehörig användare kan ta bort eller arkivera; sekundär samredigerare kan inte göra det.
- Event med historik bevaras genom cancel och arkivering med obligatorisk orsak.
- Arkiverade event filtreras bort från den aktiva kalenderprojektionen men kan fortfarande finnas kvar för historik och audit.
- Cancel återkallar alla icke återkallade kallelser, återkallar utfärdade svarstoken och skapar en notifieringsrad per berörd person i samma transaktion.
- Livscykelkommandon använder förväntad revision, eventradslås, advisory lock, idempotens, audit och domain outbox.
- Permanent purge exponeras endast för `service_role`, kräver minst 365 dagars retention och stoppas av skyddad Match Space-/ekonomihistorik.

## Klientbeteende

- `Ta bort utkast` visas endast via serverns `delete`-action och kräver explicit bekräftelse.
- `Arkivera event` visas för inställda eller genomförda event och kräver en orsak.
- Fel vid stale revision eller nytillkommen historik visas neutralt och kalendern laddas om efter en lyckad åtgärd.

## Verifiering

- `flutter analyze`: godkänd utan problem.
- Kontraktstest tillagt i `test/cal04_safe_event_lifecycle_test.dart`.
- Riktad Flutter-testkörning återstår eftersom testwrappen återkommande fastnar utan output i aktuell miljö.
- SQL-runtime återstår eftersom lokal Docker/PostgreSQL inte är tillgänglig och Supabase live inte får ändras utan separat godkännande.
- Fysisk delete/cancel/archive-grind återstår.

### Fysisk liveprojektion 2026-08-28

- Ett avgränsat testevent kunde skapas och ställas in via appens ordinarie flöde. Backvarningen för osparad redigering passerade båda grenarna utan att den sparade titeln ändrades.
- Efter `Inställd` returnerade den anslutna projektionen endast `revise`/restore och ingen `archive`-action. Klienten dolde därför arkivering korrekt fail-closed.
- Den lokala CAL-04-migrationen innehåller redan regeln som ger `archive` för `cancelled`/`completed` när aktören kan hantera primärlagets eventdelning. Skillnaden ligger därmed mellan lokal migrationsnivå och ansluten liveprojektion, inte i klientens knappvillkor.
- Testeventet `rel02 osparat test` kvarstår synligt som `Inställd`. Ingen direkt Supabase-liveändring eller kringgång av servercapability gjordes. Full cancel/archive/delete-passering väntar på separat godkänd migrations-/runtimegrind.

## Ändrade huvudfiler

- `supabase/migrations/20260827072045_cal04_safe_event_lifecycle.sql`
- `lib/src/features/calendar/calendar_models.dart`
- `lib/src/features/calendar/calendar_services.dart`
- `lib/src/features/calendar/calendar_surface.dart`
- `test/cal04_safe_event_lifecycle_test.dart`

Ingen Supabase-liveändring, produktionsprovisionering, webtool eller workspace har genomförts. Paketidentiteten är fortsatt `com.teamzone.teamzone`.
