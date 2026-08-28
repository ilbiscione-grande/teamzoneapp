# CAL-01 – kalenderns vyer och filter

Datum: 2026-08-27  
Status: lokalt genomförd, fysisk/testgrind återstår

## Levererat

- Kalendern erbjuder fyra direkt valbara lägen med fullständiga namn: Agenda, Månad, Vecka och Dag.
- Alla lägen använder samma `listCalendar`-resultat, stabila sortering och `CalendarEventSummary`; ingen parallell eventdata eller ny RPC har skapats.
- Lagfilter och eventtypfilter appliceras genom samma projektion före vy-rendering.
- Föregående period, Idag och Nästa period följer valt läge: dag, vecka eller månad.
- Agenda visar event från vald dag framåt och inkluderar pågående nattpass.
- Månad visar ett 6×7-rutnät med kompakt eventpreview och direkt öppning av EventDetails.
- Vecka visar sju begripliga dagssektioner på mobil och en sjudagarsöversikt på tablet/desktop.
- Dag visar all-day- eller lokal klocktid, lag, eventtyp, plats och status.
- Alla vyer använder samma intervallöverlapp så nattpass och event över datumgräns visas på relevanta dagar.
- Presentationen ändras efter bredd men inga capabilities eller actions förändras mellan mobil, tablet och desktop.

## Tidskontrakt

- Serverns UTC-instants parsas fortsatt med `DateTime.parse` och jämförs efter konvertering till enhetens lokala kalenderdag.
- Dags-, vecko- och månadsgränser skapas som lokala `DateTime`-gränser, vilket bevarar lokala midnätter över DST.
- Heldagsevent använder befintligt explicit `all_day`-fält och S03:s validerade lokala midnattsgränser.
- Testkontrakt täcker nattpass på två dagar, heldag på DST-dag samt explicita `+01:00`/`+02:00`-instants över svensk vår-DST.

## Filer

- `lib/src/features/calendar/calendar_models.dart`
- `lib/src/features/calendar/calendar_surface.dart`
- `lib/src/core/localization/app_strings.dart`
- `test/cal01_calendar_views_test.dart`

## Verifiering

- `flutter analyze`: inga problem.
- Ett mobilt widgettest samt två projektionstester för filter, vyer, nattpass, heldag och DST har lagts till.
- Flutter-testwrappen startade utan output även med `--no-pub` och avbröts efter begränsad väntan; testresultat anges därför inte som godkänt.
- Befintlig S03-serverprojektion, cursor-pagination, all-day-guard och privata Realtime-invalidation återanvänds oförändrade.
- Supabase live har inte ändrats.

## Kvarstående grindar

- CAL-01-testet och kalenderregressionen ska köras när Flutter-testwrappen svarar.
- Fysisk visuell kontroll av månad/vecka på phone/tablet/desktop återstår.
