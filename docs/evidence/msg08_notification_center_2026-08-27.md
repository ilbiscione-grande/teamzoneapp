# MSG-08 – Notification center utan Watchpoints

## Lokalt genomfört

- Befintlig notifierings-outbox används som gemensam källa; ingen parallell eller enhetsspecifik notishistorik skapas.
- Read/dismiss-status synkas per konto och olästa notiser visas med badge.
- Projektionen visar serverberäknad kategori, svensk titel, dataminimerad preview och tillåten deep link. Meddelandebody, token och person-ID exponeras inte.
- Meddelanden öppnar rätt inkorgstråd och kallelser/event öppnar kalenderns eventvy.
- Enskilda notiser kan läsas eller svepas bort och alla kan markeras lästa idempotent.
- Swipe-dismiss väntar på serverbekräftelse innan raden tas bort; vid nätverks-/behörighetsfel ligger notisen kvar och ett säkert fel visas.
- Privat Realtime-invalidering uppdaterar notisbadgen mellan enheter.
- Eventtyper för Watchpoints, Assistant Coach och AC-signaler filtreras explicit bort. AC introduceras inte före den senare AC-vågen.

## Verifierat lokalt

- Dart-format körd direkt med SDK-binären.
- Statisk kontraktsgrind täcker lässtatus, dataminimering, deep links, privat Realtime och borttagna Watchpoints/AC-signaler.
- Riktade MSG-07/08- och HOME-04-tester passerade 14/14, inklusive serverbekräftad dismiss/rollback.
- `dart analyze lib test` passerade utan anmärkning efter att bottom-sheet-contexten bundits till samma livscykelkontroll över async-gapet.
- Ingen Supabase-liveändring eller produktionsprovisionering är gjord.

## Återstår

- PostgreSQL-runtime/advisors när en godkänd lokal databas är tillgänglig.
- Fysisk tvåenhetsverifiering av badge, read/dismiss och deep links.
