# HOME-04 – Gemensam uppmärksamhetsmodell

## Lokalt genomfört

- Ett gemensamt prioritetskontrakt används för saknad närvaro/cancel, kallelser, event, meddelanden och övrigt.
- Notification Center projicerar `canonical_key` och `priority`, sorterar efter samma nivåer och väljer endast senaste posten per domännyckel.
- Read/dismiss på en notifiering appliceras på hela den kanoniska domänhändelsen så att en äldre reminder eller leveranspost inte återuppstår som en ny separat uppgift.
- Hemmets rollkort använder samma prioriteringsnivåer och dedupliceringsfunktion.
- Ett event som redan representeras av en kallelse visas inte igen som separat nästa-event-kort. Ledarens nästa event upprepas inte om det redan ligger under Idag.
- Mobil och större skärmar använder samma objekt, routes och mutationscallbacks. Endast kompositionen ändras mellan prioriterad enkelkolumn och flerpanelslayout.
- Klienten räknar om notifieringsprioritet från samma gemensamma kategorikontrakt och deduplicerar defensivt på `canonical_key`; vid lika prioritet behålls den senaste posten deterministiskt.

## Verifierat lokalt

- HOME-04, MSG-08 och HOME-01–HOME-03: 25/25 riktade tester passerar.
- Beteendetest verifierar att dublett med samma kanoniska nyckel väljer senaste post och att manipulerad serverprioritet ersätts av det gemensamma kategorikontraktet.
- `dart analyze lib test`: inga problem.
- Dart-format, beteendetest och statisk kontraktsgrind täcker prioritetsnivåer, kanoniska nycklar, server-/klientdeduplicering och responsiv layout utan rättighetsskillnad.
- Ingen Supabase-liveändring eller produktionsprovisionering är gjord.

## Återstår

- PostgreSQL-runtime/advisors när en godkänd lokal databas är tillgänglig.
- Fysisk verifiering av flera outboxposter för samma domänhändelse, cross-device read/dismiss och mobil/tablet/desktop.
- 2026-09-24: vårdnadshavarens Hem i Thomas lag visade S04:s kallelse utan ett extra **Nästa aktivitet**-kort för samma event. Ett skrivskyddat anrop med vårdnadshavarens behörighet bekräftade att projektionen samtidigt hade ett nästa event och en barnkallelse med exakt samma event-ID. Denna konkreta Hem-deduplicering är därmed webbverifierad; bredare notifierings-/enhetsmatris kvarstår.
- 2026-09-24: produktägaren bekräftade att samma barnidentitet och kallelsesvar förblev läsbara i mobilsmalt webbfönster utan sidscroll. Responsiv guardian-komposition är verifierad i webbläsare; separat fysisk mobilenhet och tvåflikssynk återstår.
- 2026-09-24: två samtidigt öppna guardian-Hem visade ingen synk vid ändrat S04-svar. Saknad utgående invalidiering identifierades och en tom, privat profilbunden signal efter `core.callup_responses`-insert infördes i godkänd testdatabas. Klienten använder redan denna kanal för Hem-omladdning. Riktade tester och migrering passerar; fysisk omtest kvarstår innan tvåflikssynk kan godkännas.
- 2026-09-24: produktägaren bekräftade efter omtest att ändrat S04-svar uppdaterar den andra öppna guardian-Hem-fliken utan omladdning. Webbläsarbaserad tvåflikssynk är godkänd; separat fysisk enhet och andra roller är ännu inte verifierade.
- 2026-09-24: uppmärksamhetsuppgifter i Min assistent använder fortfarande äldre `/calendar?event=…`-länkar från ledarprojektionen. Klick går nu via produktskalets normalisering och push till EventDetails, så X/Bakåt kan återgå till Min assistent. Den uppskjutna AC-signalkön aktiveras inte. Riktade regressionstester och analys passerar; fysisk kontroll återstår.
