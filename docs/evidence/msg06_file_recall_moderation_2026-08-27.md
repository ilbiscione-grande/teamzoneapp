# MSG-06 – Bilagor, återkallelse och moderation

## Utfall

- Privata filobjekt behåller stabil identitet i `core.file_objects`; den autentiserade listprojektionen lämnar bara fil-ID och visningsmetadata, aldrig bucket/object key.
- Klienten skickar fil-ID till `api.authorize_message_file`. Servern verifierar aktuell threadaccess och aktivt/ogånget objekt innan bucket/object key lämnas för en signerad URL på exakt 120 sekunder. Storage-RLS gör en andra accesskontroll.
- Bilagesändning är replay-safe: ett tappat svar kan återspelas med samma idempotensnyckel och exakt samma fil-ID:n även efter att filerna blivit aktiva. Ändrad fillista för samma nyckel avvisas som payloadkonflikt.
- Recall kräver avsändare, aktiv sendaccess, exakt revision och högst 15 minuter. Body blir tombstone, trådrevisionen ökar, föregående body får revisionerat retentionsspår och aktiva filer dras tillbaka.
- Message-update triggar nu både privat thread-resync och inbox-resync, så recall/moderation blir synligt på andra enheter.
- Report kräver harassment, sexual_content, threat, spam eller other; report är idempotent, sparar evidence hash och skapar aktiv blockering. Klienten stänger trådvyn efter lyckad report så tidigare data inte ligger kvar synligt efter accessförlust.
- Service-only moderation kräver separat reviewerprofil och orsak. Dismiss, hide_message, close_thread och legal_hold skapar immutable audit action; hide använder `[moderated]`-tombstone och drar tillbaka bilagor.
- Global radering och dubbelgodkännande lämnas till MSG-07.
- Ingen ändring har skickats till Supabase live.

## Ändringar

- `supabase/migrations/20260827154559_msg06_file_authorization_moderation.sql`
- `supabase/migrations/20260828105601_msg06_replay_safe_message_files.sql`
- `lib/src/features/messaging/messaging_models.dart`
- `lib/src/features/messaging/messaging_services.dart`
- `lib/src/features/messaging/inbox_surface.dart`
- `lib/src/core/localization/app_strings.dart`
- `test/msg06_file_recall_moderation_test.dart`
- `docs/implementation/core_app_delivery_cards.md`

## Verifiering

- Direkt Dart-format passerade för samtliga ändrade Dartfiler.
- `git diff --check` passerade.
- Statisk SQL-/klientgrind verifierade privat filprojektion, tvåstegsauktorisering, 120-sekunders URL, recall/tombstone/retention, strukturerad report/block och service-only moderation med RLS/revoke/grant.
- Uppföljningsmigrationens strukturgrind verifierade balanserade funktionsblock, authgrind, exakt replay-payload och transaktionssäker filaktivering.
- Riktade MSG-05–07-tester passerade 14/14.
- `dart analyze lib test` passerade utan anmärkning.

## Kvarvarande grindar

- Kör migreringen i isolerad PostgreSQL/Supabase/Storage-runtime och kör advisors.
- Bygg/aktivera moderatorarbetskö/operator endast efter separat driftgodkännande.
- Verifiera fysiskt med två roller: godkänd/nekad fil, utgången URL, recall före/efter 15 minuter, report/block och resync.
