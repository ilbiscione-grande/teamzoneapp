# MSG-03 – Announcement och lässtatus

## Utfall

- Aktiv ledare eller klubbfunktionär kan skapa ett announcement med rubrik till mottagare som serverns relationsregel tillåter.
- Endast aktiv skapare/moderator kan skicka i announcementtråden. Mottagare ser meddelandena men får ingen svarskompositör.
- `core.announcement_reads` är en separat, RLS-stängd per-deltagare-readmodell; vanliga trådar fortsätter använda `core.message_reads`.
- Trådlistning och enskild läsmarkering väljer readmodell efter trådtyp.
- Markera alla är ett idempotent serverkommando som verifierar valda kontexter och uppdaterar båda readmodellerna atomiskt.
- Klienten visar Info som eget skapandealternativ och Markera alla som lästa när någon tråd är oläst.
- Ingen ändring har skickats till Supabase live.

## Ändringar

- `supabase/migrations/20260827145227_msg03_announcement_read_status.sql`
- `lib/src/features/messaging/messaging_models.dart`
- `lib/src/features/messaging/messaging_services.dart`
- `lib/src/features/messaging/inbox_surface.dart`
- `lib/src/core/localization/app_strings.dart`
- `test/msg03_announcement_read_status_test.dart`
- `docs/implementation/core_app_delivery_cards.md`

## Verifiering

- Direkt Dart-format passerade för samtliga ändrade Dartfiler.
- `git diff --check` passerade.
- Statisk SQL-grind bekräftade balanserade funktionsblock, separat readtabell med RLS, authkontroller, explicit revoke/grant samt typstyrd enskild och samlad läsmarkering.
- Riktad `flutter test test/msg03_announcement_read_status_test.dart` gav ingen output inom 30 sekunder i den kända lokala Flutter-wrapperlåsningen och avbröts kontrollerat; ingen process lämnades igång.

## Kvarvarande grindar

- Kör migreringen i isolerad PostgreSQL/Supabase-runtime och kör advisors.
- Kör riktat Flutter-test och analys när den lokala wrappern fungerar.
- Verifiera fysiskt med leader/player/guardian: skapa och ta emot announcement, read-only, unread, öppna/läsa och Markera alla.
