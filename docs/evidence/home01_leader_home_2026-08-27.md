# HOME-01 – Ledarens Hem

## Lokalt genomfört

- Ledare får en separat, serververifierad hemprojektion för vald lagkontext.
- Dagens aktiviteter och nästa planerade aktivitet visar tid, plats, status och deep link till EventDetails.
- Deterministiska åtgärdskort visar obesvarade kallelser och saknad närvaro per event endast när ledaren har rätt serverbehörighet.
- Snabbvägar för kalender, laget och inkorgen beräknas utifrån capabilities; klienten uppfinner inga behörigheter.
- Mobil prioriterar uppmärksamhetskort, dagens arbete och snabba handlingar i en kolumn. Tablet/desktop använder tvåkolumnslayout och benämningen planering/administration.
- Assistant Coach-kortet har tagits bort från Hem. Inga Watchpoints eller AC-signaler visas före den senare AC-vågen.
- Event-management-grants synkar squad- och attendance-capabilities med samma giltighetstid även för framtida ledartilldelningar.
- Om den separata ledarprojektionen faller tillbaka till kontextbunden cache märks den explicit som inaktuell och Hem visar offline samt senaste servergenereringstid; gamla åtgärdskort presenteras inte tyst som färska.

## Verifierat lokalt

- `flutter test test/home01_leader_home_test.dart`: 5/5 passerar, inklusive markerad och kontextisolerad stale-cache.
- Regression för HOME-02/HOME-03: 8/8 passerar.
- `dart analyze lib test`: inga problem.
- Dart-format och statisk kontraktsgrind täcker kontextisolering, capabilities, uppgifter, deep links, responsiv layout och frånvaro av AC/Watchpoints.
- Ingen Supabase-liveändring eller produktionsprovisionering är gjord.

## Återstår

- PostgreSQL-runtime/advisors när en godkänd lokal databas är tillgänglig.
- Fysisk verifiering med ledare i minst två lagkontexter och mobil/tablet/desktop.
