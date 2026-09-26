# CAL-04 – säker eventlivscykel och radering

Datum: 2026-08-27, kompletterad 2026-09-20  
Status: slutförd – hosted, regressionstestad och fysiskt verifierad

## Levererat

- Direkt borttagning kräver ett opublicerat, fristående draft-event på revision 1.
- Direkt borttagning blockeras av serie, delat lag, trupp, kallelse, närvaro, Match Space eller sponsorbindning.
- Endast primärlagsbehörig användare kan ta bort eller arkivera; sekundär samredigerare kan inte göra det.
- Event med historik bevaras genom cancel och arkivering med obligatorisk orsak.
- Arkiverade event filtreras bort från den aktiva kalenderprojektionen men kan fortfarande finnas kvar för historik och audit.
- Arkiverade event kan visas separat via kalenderfiltret, med arkiveringsdatum, orsak och bevarad ursprungsstatus.
- Arkiverade event är skrivskyddade och kan återställas av primärlagets behöriga ledare. Återställningen tar bort arkivmarkeringen men behåller statusen `cancelled` eller `completed`.
- Cancel återkallar alla icke återkallade kallelser, återkallar utfärdade svarstoken och skapar en notifieringsrad per berörd person i samma transaktion.
- Livscykelkommandon använder förväntad revision, eventradslås, advisory lock, idempotens, audit och domain outbox.
- Permanent purge exponeras endast för `service_role`, kräver minst 365 dagars retention och stoppas av skyddad Match Space-/ekonomihistorik.

## Klientbeteende

- `Ta bort utkast` visas endast via serverns `delete`-action och kräver explicit bekräftelse.
- `Arkivera event` visas för inställda eller genomförda event och kräver en orsak.
- På övriga event är arkiveringsknappen synlig men inaktiv, med tooltip/snackbar som förklarar livscykelkravet.
- `Visa arkiverade event` byter från den aktiva kalenderprojektionen till en separat historiklista. Detaljsidan visar orsak och erbjuder `Återställ från arkiv` efter bekräftelse.
- Fel vid stale revision eller nytillkommen historik visas neutralt och kalendern laddas om efter en lyckad åtgärd.

## Verifiering

- `flutter analyze`: godkänd utan problem 2026-09-20.
- 15 riktade kalender-/livscykel-/eventdetaljtester passerar, inklusive arkivfilter, metadata, skrivskydd och återställningskommando.
- Migration `20260919211602_cal04_archived_event_recovery.sql` är applicerad och bekräftad i migrationshistoriken för det godkända Supabase-testprojektet `hgcshgunvooyudvrcpig`.
- Draft delete, cancel, återställning från cancel och archive är fysiskt verifierade i webbappen.
- Arkivlista, skrivskyddad detalj och återställning från arkiv är fysiskt verifierade i webbappen 2026-09-20. Eventet försvann ur arkivet och återkom med bevarad status och historik.

### Fysisk liveprojektion 2026-08-28

- Ett avgränsat testevent kunde skapas och ställas in via appens ordinarie flöde. Backvarningen för osparad redigering passerade båda grenarna utan att den sparade titeln ändrades.
- Efter `Inställd` returnerade den anslutna projektionen endast `revise`/restore och ingen `archive`-action. Klienten dolde därför arkivering korrekt fail-closed.
- Den lokala CAL-04-migrationen innehåller redan regeln som ger `archive` för `cancelled`/`completed` när aktören kan hantera primärlagets eventdelning. Skillnaden ligger därmed mellan lokal migrationsnivå och ansluten liveprojektion, inte i klientens knappvillkor.
- Testeventet `rel02 osparat test` kvarstår synligt som `Inställd`. Ingen direkt Supabase-liveändring eller kringgång av servercapability gjordes. Full cancel/archive/delete-passering väntar på separat godkänd migrations-/runtimegrind.

## Ändrade huvudfiler

- `supabase/migrations/20260827072045_cal04_safe_event_lifecycle.sql`
- `supabase/migrations/20260919211602_cal04_archived_event_recovery.sql`
- `lib/src/features/calendar/calendar_models.dart`
- `lib/src/features/calendar/calendar_services.dart`
- `lib/src/features/calendar/calendar_surface.dart`
- `test/cal04_safe_event_lifecycle_test.dart`

Den uttryckligen godkända CAL-04-migrationen har applicerats enbart i nuvarande Supabase-testprojekt. Ingen produktionsprovisionering, webtool eller workspace har genomförts. Paketidentiteten är fortsatt `com.teamzone.teamzone`.
