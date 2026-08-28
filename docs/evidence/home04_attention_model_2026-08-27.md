# HOME-04 – Gemensam uppmärksamhetsmodell

## Lokalt genomfört

- Ett gemensamt prioritetskontrakt används för saknad närvaro/cancel, kallelser, event, meddelanden och övrigt.
- Notification Center projicerar `canonical_key` och `priority`, sorterar efter samma nivåer och väljer endast senaste posten per domännyckel.
- Read/dismiss på en notifiering appliceras på hela den kanoniska domänhändelsen så att en äldre reminder eller leveranspost inte återuppstår som en ny separat uppgift.
- Hemmets rollkort använder samma prioriteringsnivåer och dedupliceringsfunktion.
- Ett event som redan representeras av en kallelse visas inte igen som separat nästa-event-kort. Ledarens nästa event upprepas inte om det redan ligger under Idag.
- Mobil och större skärmar använder samma objekt, routes och mutationscallbacks. Endast kompositionen ändras mellan prioriterad enkelkolumn och flerpanelslayout.

## Verifierat lokalt

- Dart-format och statisk kontraktsgrind täcker prioritetsnivåer, kanoniska nycklar, server-/klientdeduplicering och responsiv layout utan rättighetsskillnad.
- Ingen Supabase-liveändring eller produktionsprovisionering är gjord.

## Återstår

- PostgreSQL-runtime/advisors när en godkänd lokal databas är tillgänglig.
- Flutter test/analyze när wrappern kan slutföra utan låsning.
- Fysisk verifiering av flera outboxposter för samma domänhändelse, cross-device read/dismiss och mobil/tablet/desktop.
