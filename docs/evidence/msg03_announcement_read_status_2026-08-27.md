# MSG-03 – Announcement och lässtatus

## Utfall

- Aktiv ledare eller klubbfunktionär kan skapa ett announcement med rubrik till mottagare som serverns relationsregel tillåter.
- Skapare och mottagare materialiseras från samma aktiva, tidsaktuella klubb-/laguppdrag som behörighetskontrollen godkänner; en förändrad relation avbryter hela transaktionen utan tom eller otillgänglig tråd.
- Ett announcement är ett avslutat informationsobjekt med exakt ett initialt meddelande. Varken skapare eller mottagare får en svarskompositör efter publicering, och servern nekar följdmeddelanden när trådens revision har nått 2.
- `core.announcement_reads` är en separat, RLS-stängd per-deltagare-readmodell; vanliga trådar fortsätter använda `core.message_reads`.
- Trådlistning och enskild läsmarkering väljer readmodell efter trådtyp.
- Markera alla är ett idempotent serverkommando som verifierar valda kontexter och uppdaterar båda readmodellerna atomiskt.
- Klienten visar Anslag endast för behörig ledare/funktionär. Dialogen visar exakt målgrupp och omfattning med lag-/klubbnamn före utskick.
- Olästa anslag ligger i en separat, visuellt avvikande uppmärksamhetssektion över vanliga konversationer. Efter läsning flyttas de till ett hopfällt anslagsarkiv.
- Anslagsdetaljen presenteras som ett informationsmeddelande med rubrik, avsändare, tid och sammanhängande markerbar text i stället för chattbubblor.
- MSG-03-migrationerna är applicerade i den uttryckligt godkända Supabase-testdatabasen.

## Ändringar

- `supabase/migrations/20260827145227_msg03_announcement_read_status.sql`
- `supabase/migrations/20260828103629_msg03_bind_announcement_participants_to_assignments.sql`
- `supabase/migrations/20260922043656_msg03_role_group_announcements.sql`
- `supabase/migrations/20260922074609_msg03_grant_role_group_announcement_execution.sql`
- `supabase/migrations/20260922131951_msg03_close_announcement_after_initial_message.sql`
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
- Uppföljningsmigrationens strukturkontroll bekräftade balanserade dollarcitat/parenteser, explicit `auth.uid()`-grind och tidsbundna assignmentvillkor.
- Riktade MSG-01–04-tester passerade 19/19.
- `dart analyze lib test` passerade utan anmärkning.
- Riktat MSG-03-test passerar 6/6 och full `flutter analyze` är ren efter rollgrupps-, uppmärksamhets-/arkiv- och informationsvyändringarna.
- Hostad rollback-verifiering bekräftade att första atomiska anslagsmeddelandet till spelare i Thomas lag lyckas och att ett följdmeddelande till ett publicerat anslag nekas med `announcement_closed`.
- Fysisk webbverifiering bekräftade publicering från Coach Emilson till spelare i Thomas lag, uppmärksamhetsplacering, skrivskyddad informationsvy och flytt till anslagsarkivet efter läsning.
- Två anslag (`Guardianverifiering 1` och `Guardianverifiering 2`) skickades via samma serverkommando till vårdnadshavaren i Thomas lag. Databasen visade först `unread_count = 1` för vardera. Produktägaren verifierade att Markera alla tog bort dem från uppmärksamhetslistan och att båda fanns kvar i Arkiverade anslag. Efter åtgärden visade `core.announcement_reads` `through_revision = 2` och `unread_count = 0` för båda. MSG-03 är därmed fysiskt godkänd även för guardian och samlad läsmarkering.

## Status

- Samtliga MSG-03-grindar är godkända.
