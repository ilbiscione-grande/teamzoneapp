# CAL-07 – svar, guardian och påminnelse

Datum: 2026-08-27, kompletterad 2026-09-20  
Status: hosted och delvis fysiskt verifierad; push-actiongrind återstår

## Levererat

- Spelare och vårdnadshavare använder samma auktoritativa `callup.response.recorded.v2`-transition.
- Direkt svar kräver en aktiv person–profil-länk till mottagaren.
- Guardian acting-as kräver en aktiv guardianrelation vid svarstidpunkten och barnets person-id sparas på response och audit command.
- Accepterat, kanske och avböjt är separata svar.
- Avböjt kräver en av `illness`, `injury`, `unavailable`, `transport` eller `other`.
- Fritext krävs endast för `other`, är begränsad till 2–500 tecken och avvisas för övriga koder.
- Påminnelse är endast möjlig för en giltig pending callup och har sex timmars server-cooldown.
- Reminder använder separat command/event type och separat notifieringsleveransstatus i projektionen.
- Retry med samma idempotency key returnerar tidigare resultat före stale/state-kontroll.
- Push-actiontoken lagras endast som hash, binds till callup och mottagarperson, scopes till tillåtna svar och gäller högst 15 minuter.
- En ny token återkallar tidigare utfärdad token för samma callup. Cancel återkallar alla öppna token.
- Token konsumeras under radlås i samma transaktion som svaret; retry med samma command-id är idempotent.

## Klient

- Egen spelarkallelse och guardian-kallelse visar samma svarsalternativ.
- Guardianläge märks som `svar som vårdnadshavare`.
- Avböjning öppnar val av strukturerad anledning och visar fritext endast för Annat.
- Påminnelseknappen döljs under cooldown och projektionen visar antal samt senaste leveransstatus.
- Behörig ledare samt den berörda personen/vårdnadshavaren ser avböjandeorsaken direkt på personens deltagarrad. Övriga lagkamrater får aldrig orsaken i serverprojektionen.

## Verifiering

- `flutter analyze`: godkänd utan problem.
- 12/12 riktade CAL-07/CAL-11-tester passerar, inklusive modellkoppling och visning av behörighetsfiltrerad avböjandeorsak.
- SQL-runtime är applicerad på testprojektet `hgcshgunvooyudvrcpig`; migration `20260920125856_cal07_visible_decline_reasons.sql` finns i både lokal och remote migrationshistorik.
- Fysisk webbgrind 2026-09-20 godkände spelarens Acceptera/Avböj, obligatorisk strukturerad avböjandeorsak, markerad vald svarsknapp, ledarens Påminn och bestående `Påmind` samt visning av avböjandeorsaken på deltagarraden.
- Fysisk guardian acting-as verifierades 2026-09-20 på `Testspelare S04`: deltagarraden märktes `Svara som vårdnadshavare`, Avböj sparades och avböjandeorsaken visades på samma rad. En separat egen kallelse märktes samtidigt korrekt `Din kallelse`, vilket gjorde relationstypen tydlig.
- Push-actiontoken återstår. Extern pushleverans aktiveras inte inom denna grind.

## Ändrade huvudfiler

- `supabase/migrations/20260827074757_cal07_callup_response_guardian_reminder_tokens.sql`
- `supabase/migrations/20260920125856_cal07_visible_decline_reasons.sql`
- `lib/src/features/calendar/calendar_models.dart`
- `lib/src/features/calendar/calendar_services.dart`
- `lib/src/features/calendar/event_details_page.dart`
- `lib/src/core/localization/app_strings.dart`
- `test/cal07_callup_response_guardian_reminder_test.dart`

Endast den uttryckligt godkända migrationen ovan ändrades i Supabase-testprojektet. Ingen produktionsprovisionering, webtool eller workspace har genomförts. Paketidentiteten är fortsatt `com.teamzone.teamzone`.
