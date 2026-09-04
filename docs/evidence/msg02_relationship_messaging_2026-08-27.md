# MSG-02 – Grupp, direkt och relationsstyrd kontakt

## Utfall

- En central serverfunktion avgör tillåtna relationer för mottagarsökning, trådskapande, deltagartillägg och send.
- Klubbfunktionär ger aldrig automatiskt klubbvid mottagaråtkomst; bred kontakt kräver explicit `club.messaging.manage` i rätt aktivt scope.
- Player-to-player är av som standard. Spelare kan kontakta relevanta ledare/vårdnadshavare och ledare kan kontakta aktiva roller i aktuell klubb-/lagkontext.
- Gruppskapande kräver namn och minst en mottagare; direktkonversation kräver exakt en mottagare.
- Endast aktiv skapare/moderator kan lägga till deltagare i en grupp, och servern återvaliderar varje mottagare.
- Cross-club-ledarkontakt är fortsatt begränsad till verifierade vuxna ledare, visar endast namn/klubb/lag, begränsas till 3 förfrågningar per 24 timmar och 10 per 30 dagar och skapar tråd först efter acceptans.
- Blockering stoppar sökning, skapande, tillägg och fortsatt send.
- Acceptans av cross-club-förfrågan återvaliderar nu båda ledarnas vuxenverifiering och aktiva ledaruppdrag, att de fortfarande tillhör olika klubbar samt att ingen blockering har tillkommit. Förändrad relation skapar därför ingen tom eller obehörig tråd.
- Ingen ändring har skickats till Supabase live.

## Ändringar

- `supabase/migrations/20260827144006_msg02_relationship_messaging.sql`
- `supabase/migrations/20260828112000_msg02_revalidate_cross_club_acceptance.sql`
- `lib/src/features/messaging/messaging_services.dart`
- `lib/src/features/messaging/inbox_surface.dart`
- `lib/src/core/localization/app_strings.dart`
- `test/msg02_relationship_messaging_test.dart`
- `docs/implementation/core_app_delivery_cards.md`

## Verifiering

- Direkt Dart-format passerade för ändrade Dartfiler.
- `git diff --check` passerade.
- Statiska SQL-kontroller bekräftade balanserade dollarcitat/parenteser och att relationsregeln används i samtliga fyra skyddade vägar.
- Riktade MSG-02-, MSG-07- och idempotens-/observabilitytester passerade 21/21.
- `dart analyze lib test` passerade utan anmärkning.

## Kvarvarande grindar

- Kör migreringen i en isolerad PostgreSQL/Supabase-runtime och kör advisors.
- Verifiera fysiskt med leader, player och guardian: tillåten och nekad direktkontakt, gruppskapande, deltagartillägg, blockering och cross-club-acceptans.
