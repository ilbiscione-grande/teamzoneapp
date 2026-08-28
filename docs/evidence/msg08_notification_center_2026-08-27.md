# MSG-08 – Notification center utan Watchpoints

## Lokalt genomfört

- Befintlig notifierings-outbox används som gemensam källa; ingen parallell eller enhetsspecifik notishistorik skapas.
- Read/dismiss-status synkas per konto och olästa notiser visas med badge.
- Projektionen visar serverberäknad kategori, svensk titel, dataminimerad preview och tillåten deep link. Meddelandebody, token och person-ID exponeras inte.
- Meddelanden öppnar rätt inkorgstråd och kallelser/event öppnar kalenderns eventvy.
- Enskilda notiser kan läsas eller svepas bort och alla kan markeras lästa idempotent.
- Privat Realtime-invalidering uppdaterar notisbadgen mellan enheter.
- Eventtyper för Watchpoints, Assistant Coach och AC-signaler filtreras explicit bort. AC introduceras inte före den senare AC-vågen.

## Verifierat lokalt

- Dart-format körd direkt med SDK-binären.
- Statisk kontraktsgrind täcker lässtatus, dataminimering, deep links, privat Realtime och borttagna Watchpoints/AC-signaler.
- Ingen Supabase-liveändring eller produktionsprovisionering är gjord.

## Återstår

- PostgreSQL-runtime/advisors när en godkänd lokal databas är tillgänglig.
- Flutter test/analyze när wrappern kan slutföra utan låsning.
- Fysisk tvåenhetsverifiering av badge, read/dismiss och deep links.
