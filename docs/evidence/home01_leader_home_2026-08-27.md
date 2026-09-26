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
- 2026-09-23: fysisk webbkontroll påbörjad med ledarkonto i kontexten **Thomas lag**. Hem visar **Idag: Inga aktiviteter**, **Nästa aktivitet: Träning** samt planeringsmeny i högerkolumnen. Kontroll efter byte till annat ledarlag återstår.
- 2026-09-23: samma konto bytte till **Nytt lag**. Hem visade fortsatt inga aktiviteter idag men **Nästa aktivitet: vs Sävsjö FF** i stället för Thomas-lagets träning; planeringsmenyn fanns kvar. Produktägaren bekräftade att innehållet ändras med lagkontexten. Återbyte och responsiv kontroll återstår.
- 2026-09-23: återbyte till **Thomas lag** visade åter **Nästa aktivitet: Träning** utan Sävsjö-matchen. Tvåvägsbyte mellan ledarens lagkontexter är därmed webbverifierat. Mobil/smal responsiv layout återstår.
- 2026-09-23: i smalt webbläsarfönster kunde produktägaren läsa **Idag** och **Nästa aktivitet** utan horisontell scroll; planeringsmenyn låg under aktivitetskorten i stället för i högerkolumn. Smal responsiv webbvy är verifierad. Länken från nästa aktivitet återstår i denna genomgång.
- 2026-09-23: **Nästa aktivitet: Träning** öppnade rätt EventDetails. Bakåt gick till ledarens Hem, men X gick felaktigt till Kalender. Orsaken var att Hem använde GoRouters `go` för eventet, så EventDetails saknade en poppbar föräldrasida. Hem öppnar nu bara eventdetaljer med `push`; övriga snabbvägar behåller `go`. X poppar till ursprungssidan och direktöppnade event har kvar Kalender som säker fallback. HOME-01-test 6/6 och riktad analys passerar; fysisk omtest efter webbbygge återstår.
- 2026-09-23: efter konfigurerat releasebygge på port 5000 öppnade produktägaren Träning från Thomas-lagets Hem och bekräftade att X nu återgår till Hem. Navigering från Hem via både X och Bakåt är webbverifierad. Direktöppnat event utan föregående sida återstår att kontrollera.
- 2026-09-23: vid försök att kopiera eventlänken upptäckte produktägaren att adressfältet fortfarande visade `/home` när eventdetaljen var pushad. Orsaken finns i lokalt installerade `go_router` 17.3.0: `optionURLReflectsImperativeAPIs` är `false` som standard. Alla pushade TeamZone-rutter i produktskalet är egna direktlänksbara GoRoutes; webbappen aktiverar nu URL-reflektion före routerinitialisering. Ett widgettest verifierar att pushad eventadress syns som `/calendar/event/...` och att pop återgår till `/home`; HOME-01 7/7, angränsande HOME-01/CAL-01/TEAM-01 16/16 och analys passerar. Konfigurerad lokal releasewebb byggdes och `/home` svarar 200 på port 5000. Fysisk kontroll av kopierad direktlänk återstår.
- 2026-09-23: efter omladdning bekräftade produktägaren att ett event öppnat från Hem nu visar `/calendar/event/...` i webbläsarens adressfält. Kopierbar URL är webbverifierad; öppning i ny flik och X-fallback återstår.
- 2026-09-23: produktägaren kopierade eventadressen till en ny flik. Samma Träning laddades, och X gick till Kalender eftersom den nya fliken saknade en föregående appsida. Navigering från Hem, kopierbar adress, direktöppning och säker X-fallback är webbverifierade.
- 2026-09-24: äldre ledaruppgifter projicerar fortfarande `/calendar?event=…`. Produktskalet normaliserar nu sådana länkar till EventDetails-routen före navigering; från Hem öppnas detaljen med push så X/Bakåt återgår till Hem. Samma regel gäller vid kall direktlänk. Klienttest och analys passerar; fysisk kontroll av en äldre uppgift återstår. Ingen databasmigrering eller AC-aktivering gjordes.

## Återstår

- PostgreSQL-runtime/advisors när en godkänd lokal databas är tillgänglig.
- Fysisk verifiering med ledare i minst två lagkontexter och mobil/tablet/desktop.
