# CAL-07 – svar, guardian och påminnelse

Datum: 2026-08-27  
Status: lokalt genomförd, runtimegrindar återstår

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

## Verifiering

- `flutter analyze`: godkänd utan problem.
- Kontraktstest tillagt i `test/cal07_callup_response_guardian_reminder_test.dart`.
- SQL-runtime återstår eftersom lokal Docker/PostgreSQL saknas och Supabase live inte får ändras utan separat godkännande.
- Flutter-testwrapper och fysisk player/guardian/reminder/push-action-grind återstår.

## Ändrade huvudfiler

- `supabase/migrations/20260827074757_cal07_callup_response_guardian_reminder_tokens.sql`
- `lib/src/features/calendar/calendar_models.dart`
- `lib/src/features/calendar/calendar_services.dart`
- `lib/src/features/calendar/calendar_surface.dart`
- `lib/src/core/localization/app_strings.dart`
- `test/cal07_callup_response_guardian_reminder_test.dart`

Ingen Supabase-liveändring, produktionsprovisionering, webtool eller workspace har genomförts. Paketidentiteten är fortsatt `com.teamzone.teamzone`.
