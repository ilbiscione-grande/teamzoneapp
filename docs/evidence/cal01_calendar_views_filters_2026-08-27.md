# CAL-01 – kalenderns vyer och filter

Datum: 2026-08-27  
Status: lokalt genomförd; samtliga fyra mobilvyer och overflow-regression fysiskt verifierade, tablet/desktop och eventfylld Vecka/Dag återstår

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
- Riktad CAL-01-körning passerar 3/3 och riktad analys är ren.
- Befintlig S03-serverprojektion, cursor-pagination, all-day-guard och privata Realtime-invalidation återanvänds oförändrade.
- Supabase live har inte ändrats.

### Fysisk Mi 9-regression 2026-08-28

- Agenda renderade vyval, lag-/eventtypfilter, datumbläddring, tomläge, `Nytt event` och Min assistent-FAB utan overflow.
- Första Månadskörningen hittade `BOTTOM OVERFLOWED BY 12 PIXELS` i en mobilcell med tre event och summeringsrad.
- Mobilcellen begränsades till en eventrad plus `+N`; tablet/desktop behåller två eventrader. Widgettestet kräver nu fyra event på samma mobildag, `+3` och ingen layout-exception.
- Korrigerad audit-debugbuild `629CC42B1C051FF4775A4FAE2AE532ACD5186149297D018AF361671F0FE918A3` installerades på Xiaomi Mi 9, Android 10.
- Fysisk omkörning visade fullständigt 6×7-rutnät utan röd overflow; den 16 augusti visade en ellipsiserad titel och `+2`, medan semantiken behöll hela titeln.
- Vecka och Dag renderade korrekta svenska datumintervall, periodnavigation, filter, tomläge och separata event-/assistentåtgärder utan overflow på samma build.

## Kvarstående grindar

- Eventfylld Vecka/Dag på telefon och samtliga vyer på tablet/desktop återstår.
