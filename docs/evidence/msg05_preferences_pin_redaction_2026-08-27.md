# MSG-05 – Mute, pin och pushpreferenser

## Beslut och utfall

- **Pin är kontosynkad**, inte lokal. En profil får en revisionerad rad per tråd; fästa trådar sorteras först, kan filtreras och resynkas genom privat inbox-invalidation.
- Mute är fortsatt kontosynkad och idempotent. Klienten visar pending, uppdaterar först efter serverbekräftelse och återhämtar via inbox-resync.
- Meddelandepush är frivillig och `false` om en explicit preferensrad saknas. Inställningen kan aktiveras/avaktiveras i Inbox och lagras per profil.
- Notification-claim undertrycker message-push om mottagaren saknar opt-in eller har aktiv mute. Provider/endpoint är fortsatt avstängd i väntan på separat driftgodkännande.
- En trigger reducerar message-outboxpayload till `thread_id`, `message_id` och `preview_key=new_message`. Rå body, avsändarnamn, rubrik, filnamn och URL tillåts inte i payloaden.
- Notification-workern loggar endast komponent/resultat/felkod och aldrig payload.
- Den mätta command-gatewayns lokala allowlist omfattar nu även MSG-02/03/05-kommandona.
- Klienten tillåter bara en pushinställningsdialog/-skrivning åt gången. Mute och pin låser sitt avsedda målvärde före nätverksanropet, och en mutad tråd visar den omvända, tydliga åtgärden ”Slå på notiser”.
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
- Riktade MSG-04–06-tester passerade 14/14, inklusive dubbelklicks-/stale-toggle-grinden.
- `dart analyze lib test` passerade utan anmärkning.
- 2026-09-23: produktägaren verifierade i den lokala webbappen att en fäst konversation hamnar överst i inkorgen och visas under filtret **Fästa**. Kontroll av kontosynk efter återanslutning och avfästning återstår.
- 2026-09-23: produktägaren verifierade att tystning placerar samma konversation under **Tystade** och byter åtgärden till **Slå på notiser**. Återaktivering och avfästning återstår.
- 2026-09-23: produktägaren verifierade också att **Slå på notiser** och **Lossa tråd** tar bort konversationen ur respektive filter. Den lokala webbkontrollen av pin/unpin och mute/unmute är därmed klar; separat återanslutnings-/tvåenhetskontroll återstår.
- 2026-09-23: produktägaren aktiverade **Frivilliga pushnotiser**, laddade om webbappen och bekräftade att reglaget fortfarande var på. Detta verifierar sparad preferens, inte faktisk pushleverans. Avstängning återstår att kontrollera.
- 2026-09-23: produktägaren slog av **Frivilliga pushnotiser**, laddade om och bekräftade att reglaget förblev av. Både opt-in och opt-out med persistens är webbverifierade. Testkontot lämnades med preferensen avstängd.
- 2026-09-23: produktägaren öppnade samma konto i två webbläsarsessioner. När en tråd fästes i den ena flyttades den överst i den andra utan omladdning. Kontosynkad pin och inbox-resync är därmed fysiskt webbverifierade. Mute-synk återstår.
- 2026-09-23: produktägaren tystade samma tråd i första sessionen. Den visades under **Tystade** i den andra utan omladdning; därefter slogs notiser på igen. Pin- och mute-synk mellan två webbläsarsessioner är verifierade. Faktisk pushleverans/provideraktivering och separat tvåenhetstest återstår.

## Kvarvarande grindar

- Kör migreringen i isolerad PostgreSQL/Supabase-runtime och kör advisors.
- Kör Deno check när verktyget finns lokalt.
- Verifiera med två enheter: mute/unmute, pin/unpin och ordning efter reconnect samt push opt-in/out.
- Aktivera och verifiera pushprovider/endpoints endast efter separat driftgodkännande.
