# MSG-04 – Historik, send och Realtime-resync

## Utfall

- Serverhistoriken använder unik, exklusiv `before_revision`, deterministisk revisions-/ID-sortering och `limit + 1` för explicit `has_more` och nästa cursor.
- Klienten slår ihop äldre sidor per meddelande-ID och sorterar resultatet stigande på revision, vilket skyddar mot dubbletter vid retry/resync.
- Ett nytt meddelande visas omedelbart som pending. Vid fel ligger det kvar med explicit retry; samma idempotensnyckel och samma staged-file-ID:n återanvänds.
- Efter lyckad send ersätts den optimistiska raden av serverns kanoniska meddelande.
- Varje send går fortsatt genom `internal.actor_can_access_thread(..., true)` och MSG-03:s announcement-kontroll.
- Trådvyn prenumererar på den privata `message:thread:{id}`-kanalen. Både första subscribe och reconnect utlöser debouncad hämtning av första sidan från servern.
- Trådvyn generationsmärker hämtningar. Ett äldre initial-/Realtime-svar får inte skriva över en nyare resync, och en äldre pagineringssida ignoreras om en ny first-page-hämtning har startat.
- Ingen ändring har skickats till Supabase live.

## Ändringar

- `supabase/migrations/20260827150144_msg04_message_history_cursor.sql`
- `lib/src/features/messaging/messaging_models.dart`
- `lib/src/features/messaging/messaging_services.dart`
- `lib/src/features/messaging/inbox_surface.dart`
- `lib/src/core/localization/app_strings.dart`
- `test/msg04_history_send_resync_test.dart`
- `docs/implementation/core_app_delivery_cards.md`

## Verifiering

- Direkt Dart-format passerade för samtliga ändrade Dartfiler.
- `git diff --check` passerade.
- Statisk kontraktsgrind verifierade exklusiv cursor, deterministisk ordning, continuation, idempotent retry, aktiv participantkontroll och subscribe/reconnect-resync.
- Riktade MSG-03–05-tester passerade 14/14, inklusive generationsgrinden för stale resync/pagination.
- `dart analyze lib test` passerade utan anmärkning.

## Kvarvarande grindar

- Kör migreringen i isolerad PostgreSQL/Supabase-runtime och kör advisors.
- Verifiera fysiskt med två enheter: fler än 50 meddelanden, samtidiga nya meddelanden under äldre pagination, offline send/failure/retry, reconnect och borttagen participant före retry.
