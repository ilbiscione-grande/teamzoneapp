# MSG-02 – Grupp, direkt och relationsstyrd kontakt

## Utfall

- En central serverfunktion avgör tillåtna relationer för mottagarsökning, trådskapande, deltagartillägg och send.
- Player-to-player är av som standard. Spelare kan kontakta relevanta ledare/vårdnadshavare och ledare kan kontakta aktiva roller i aktuell klubb-/lagkontext.
- Gruppskapande kräver namn och minst en mottagare; direktkonversation kräver exakt en mottagare.
- Endast aktiv skapare/moderator kan lägga till deltagare i en grupp, och servern återvaliderar varje mottagare.
- Cross-club-ledarkontakt är fortsatt begränsad till verifierade vuxna ledare, visar endast namn/klubb/lag, begränsas till 3 förfrågningar per 24 timmar och 10 per 30 dagar och skapar tråd först efter acceptans.
- Blockering stoppar sökning, skapande, tillägg och fortsatt send.
- Ingen ändring har skickats till Supabase live.

## Ändringar

- `supabase/migrations/20260827144006_msg02_relationship_messaging.sql`
- `lib/src/features/messaging/messaging_services.dart`
- `lib/src/features/messaging/inbox_surface.dart`
- `lib/src/core/localization/app_strings.dart`
- `test/msg02_relationship_messaging_test.dart`
- `docs/implementation/core_app_delivery_cards.md`

## Verifiering

- Direkt Dart-format passerade för ändrade Dartfiler.
- `git diff --check` passerade.
- Statiska SQL-kontroller bekräftade balanserade dollarcitat och att relationsregeln används i samtliga fyra skyddade vägar.
- Riktad `flutter test test/msg02_relationship_messaging_test.dart` gav ingen output inom 30 sekunder i den kända lokala Flutter-wrapperlåsningen och avbröts kontrollerat; ingen process lämnades igång.

## Kvarvarande grindar

- Kör migreringen i en isolerad PostgreSQL/Supabase-runtime och kör advisors.
- Kör riktat test och analys när Flutter-wrappern fungerar.
- Verifiera fysiskt med leader, player och guardian: tillåten och nekad direktkontakt, gruppskapande, deltagartillägg, blockering och cross-club-acceptans.
