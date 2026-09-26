# CAL-08 – atomisk närvaro

Datum: 2026-08-27, kompletterad 2026-09-20  
Status: genomförd och verifierad

## Levererat

- `unknown`, `present`, `late`, `partial` och `absent` är fem separata servervaliderade statusar.
- Unknown är neutral i både eventresultatet och befintlig Home/statistikprojektion och räknas aldrig som present eller absent.
- Late och partial kräver ett explicit minutvärde 1–1440; övriga statusar får inte bära minuter.
- Klienten skickar endast ändrade personer, men servern validerar hela batchen innan någon rad muteras.
- Varje ändring kräver `expected_revision`; ny attendance använder revision 0.
- Eventrad, attendance aggregate advisory lock och radlås serialiserar konkurrerande batcher.
- Samma idempotency key returnerar tidigare resultat före stale/state-kontroll.
- Varje sparad person får en immutable `audit.attendance_revisions`-rad med initial, correction eller late_correction.
- En ändring efter eventets sluttid plus 24 timmar kräver `event.attendance.correct_late` på relevant eventlag och en orsak på 3–500 tecken.
- Resultatet räknar varje status separat och exponerar unknown separat.

## Mobilflöde

- `Registrera närvaro` öppnar ett 92 procent högt sheet lämpat för användning under aktivitet.
- Alla deltagare visas i en rullbar lista med fem fullständiga statusnamn.
- Late/partial visar ett inlinefält för minuter.
- Flera ändringar sparas med en knapp och ett command-id.
- Sen korrigering blockeras begripligt utan capability och kräver orsak när den är tillåten.
- Vid stale revision behålls inget delresultat; användaren uppmanas ladda om.

## Verifiering

- `flutter analyze`: godkänd utan problem.
- 13/13 riktade CAL-08/CAL-11-tester passerar. Modelltest verifierar att sparat minutantal återställs till den renderade rosterraden.
- CAL-08:s SQL-runtime ingår i testprojektets synkade migrationshistorik.
- Fysisk webbgrind 2026-09-20 verifierade atomisk sparning av flera olika statusar, bestående status efter omladdning, synligt inlinefält för minuter vid `late`/`partial`, bestående minutantal samt efterföljande korrigering.
- Smal fysisk mobilkontroll verifierade att statusväljare och minutfält får plats och förblir användbara utan overflow eller klippning.

## Ändrade huvudfiler

- `supabase/migrations/20260827075525_cal08_atomic_attendance.sql`
- `lib/src/features/calendar/calendar_models.dart`
- `lib/src/features/calendar/calendar_services.dart`
- `lib/src/features/calendar/event_details_page.dart`
- `lib/src/core/localization/app_strings.dart`
- `test/cal08_atomic_attendance_test.dart`

Ingen ny Supabaseändring krävdes för 2026-09-20-fixen. Ingen produktionsprovisionering, webtool eller workspace har genomförts. Paketidentiteten är fortsatt `com.teamzone.teamzone`.
