# MSG-05 – Mute, pin och pushpreferenser

## Beslut och utfall

- **Pin är kontosynkad**, inte lokal. En profil får en revisionerad rad per tråd; fästa trådar sorteras först, kan filtreras och resynkas genom privat inbox-invalidation.
- Mute är fortsatt kontosynkad och idempotent. Klienten visar pending, uppdaterar först efter serverbekräftelse och återhämtar via inbox-resync.
- Meddelandepush är frivillig och `false` om en explicit preferensrad saknas. Inställningen kan aktiveras/avaktiveras i Inbox och lagras per profil.
- Notification-claim undertrycker message-push om mottagaren saknar opt-in eller har aktiv mute. Provider/endpoint är fortsatt avstängd i väntan på separat driftgodkännande.
- En trigger reducerar message-outboxpayload till `thread_id`, `message_id` och `preview_key=new_message`. Rå body, avsändarnamn, rubrik, filnamn och URL tillåts inte i payloaden.
- Notification-workern loggar endast komponent/resultat/felkod och aldrig payload.
- Den mätta command-gatewayns lokala allowlist omfattar nu även MSG-02/03/05-kommandona.
- Ingen ändring har skickats till Supabase live.

## Ändringar

- `supabase/migrations/20260827151434_msg05_notification_preferences_pin_redaction.sql`
- `supabase/functions/critical-flow-command/index.ts`
- `lib/src/features/messaging/messaging_models.dart`
- `lib/src/features/messaging/messaging_services.dart`
- `lib/src/features/messaging/inbox_surface.dart`
- `lib/src/core/localization/app_strings.dart`
- `test/msg05_preferences_pin_redaction_test.dart`
- `docs/implementation/core_app_delivery_cards.md`

## Verifiering

- Direkt Dart-format passerade för ändrade Dartfiler.
- `git diff --check` passerade.
- Statisk SQL-/gateway-/workergrind verifierade RLS, explicit revoke/grant, fail-closed preferens/mute, kontosynkad pin, automatisk payloadredaction och frånvaro av payloadloggning.
- Deno finns inte installerat lokalt, så separat TypeScript/Deno-kontroll återstår.
- Riktad `flutter test test/msg05_preferences_pin_redaction_test.dart` gav ingen output inom 30 sekunder i den kända lokala Flutter-wrapperlåsningen och avbröts kontrollerat; ingen process lämnades igång.

## Kvarvarande grindar

- Kör migreringen i isolerad PostgreSQL/Supabase-runtime och kör advisors.
- Kör Flutter-test/analys och Deno check när de lokala verktygen fungerar.
- Verifiera med två enheter: mute/unmute, pin/unpin och ordning efter reconnect samt push opt-in/out.
- Aktivera och verifiera pushprovider/endpoints endast efter separat driftgodkännande.
