# CAL-02 – skapa och redigera event/serie

Datum: 2026-08-27  
Status: lokalt genomförd, SQL-/fysisk/testgrind återstår

## Levererat i klienten

- Samma fullständiga editor används för nytt event och redigering.
- Formuläret omfattar titel, beskrivning, lag, eventtyp, status, start/slut, heldag, tidszon, plats och audience.
- Skapande kan sparas som utkast eller publicerat (`scheduled`).
- Audience kan väljas direkt mellan spelare, ledare, vårdnadshavare och hela klubben; minst ett val krävs.
- Engångsevent eller daglig/veckovis serie kan skapas med validerat intervall 1–52 och 2–104 förekomster.
- Serier måste vid redigering välja `Bara detta`, `Detta och framåt` eller `Hela serien`.
- EventDetails kan publicera utkast, återställa inställda event, ställa in och markera planerade event som genomförda via befintlig revisionssäker transition.
- Formuläret har osparade-ändringar-skydd och begripliga valideringsfel.

## Serverkontrakt

- `revise_event_v2` verifierar auth, `event.manage`, anchor revision, tillåtna patchfält och one/forward/all.
- Ett transaktionsbundet advisory lock serialiserar hela eventserien.
- Ny ankartid omvandlas till en delta som appliceras på varje vald förekomst; förekomster kollapsar därför inte till samma timestamp.
- Ändrad sluttid blir en gemensam validerad duration relativt varje förekomsts nya start.
- Hela-serien-redigering uppdaterar recurrence rule-local start och tidszon.
- Audience för det ägande laget ersätts atomiskt, medan framtida shared-team-specifika audience-rader bevaras inför CAL-03.
- Platsnamn återanvänds inom klubben eller skapas tenantbundet; tom plats rensar kopplingen.
- Revision, event revision snapshot, outbox, command deduplication och audit uppdateras per berörd förekomst.

## Sparade platser

- `list_saved_event_locations` kräver `event.manage` för exakt klubb-/lagkontext.
- Queryn filtrerar alltid `event_locations.club_id = target_club_id`, normaliserar dubblettnamn och returnerar högst 100 förslag.
- Ett sammansatt klubb-/normaliserat namn-/recent-index stöder queryn.
- Klienten visar högst åtta tydliga förslagschips och tillåter fortfarande ett nytt platsnamn.

## Filer

- `lib/src/features/calendar/calendar_surface.dart`
- `lib/src/features/calendar/calendar_services.dart`
- `lib/src/core/localization/app_strings.dart`
- `supabase/migrations/20260827063902_cal02_event_editor_locations.sql`
- `test/cal02_event_editor_test.dart`

## Verifiering

- `flutter analyze`: inga problem.
- Ett widgettest, ett SQL-kontraktstest och ett modelltest har lagts till.
- Flutter-testwrappen startade utan output även med `--no-pub` och avbröts efter begränsad väntan; testresultat anges därför inte som godkänt.
- Supabase/Postgres-praktikskillen styrde tenantindexet och det transaktionsbundna serielåset.
- Supabase live `hgcshgunvooyudvrcpig` har inte ändrats.

## Kvarstående grindar

- Migrationen är lokal och har inte körts mot Supabase live.
- Docker/lokal PostgreSQL saknas, så SQL-fixtures, serie-/DST-matris, `EXPLAIN` och advisors återstår.
- CAL-02-testet och kalenderregressionen ska köras när Flutter-testwrappen svarar.
- Fysisk verifiering av den långa editorn på phone/tablet/desktop återstår.
