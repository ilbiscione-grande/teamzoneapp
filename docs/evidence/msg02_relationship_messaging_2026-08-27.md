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
- De godkända MSG-02-migreringarna är applicerade i den uttryckligen godkända Supabase-testdatabasen `hgcshgunvooyudvrcpig`.

## Ändringar

- `supabase/migrations/20260827144006_msg02_relationship_messaging.sql`
- `supabase/migrations/20260828112000_msg02_revalidate_cross_club_acceptance.sql`
- `supabase/migrations/20260920224500_msg02_global_inbox_context_labels.sql`
- `supabase/migrations/20260921192106_msg02_search_cross_club_directory.sql`
- `supabase/migrations/20260921200612_msg02_descriptive_contact_requests.sql`
- `supabase/migrations/20260921202524_msg02_show_club_scoped_threads_in_team_contexts.sql`
- `supabase/migrations/20260921203502_msg02_direct_thread_counterparty_name_fallback.sql`
- `supabase/migrations/20260921205711_msg02_restore_counterparty_display_name_alias.sql`
- `supabase/migrations/20260921210307_msg02_contact_request_becomes_first_message.sql`
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

## Hosted och fysisk slutverifiering 2026-09-21

- Player-, guardian-, leader- och begränsad klubbfunktionärskontext verifierade att mottagarlistan följer den centrala relationsregeln och inte ger automatisk player-to-player- eller klubbvid åtkomst.
- Direktkonversationer återanvänder befintlig tråd. Gruppskapande och senare deltagartillägg passerade med servervaliderade mottagare.
- Inboxen samlar användarens aktiva kontexter och grupperar trådar tydligt per lag/klubb.
- Två separata verifierade ledarkonton i olika klubbar genomförde hela cross-club-flödet: katalogsökning via klubb/lag/ledare, anledning och fritext, tydlig mottagargranskning, acceptans, skapad privat tråd och tvåvägssvar.
- Kontaktförfrågans fritext visas som första meddelande med ursprunglig avsändare. Trådrubriken visar motpartens namn med klubbperson som säker reserv om profilnamn saknas.
- Den slutliga korrigeringen verifierades med ett verkligt skrivskyddat `internal.list_threads_for_actor`-anrop och kontroll att den accepterade förfrågan materialiserats som ett meddelande. Riktad regression passerade 15/15.

MSG-02 är komplett godkänd inom grundappens aktuella testomfattning.
