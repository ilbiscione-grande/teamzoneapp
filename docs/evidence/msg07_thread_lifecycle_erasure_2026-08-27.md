# MSG-07 – Trådlivscykel och global radering

## Lokalt genomfört

- Personlig, reversibel döljning lagras separat och påverkar inte övriga deltagare.
- Frivilliga grupp-, direkt- och cross-club-trådar kan lämnas; systemtrådar kan inte lämnas den vägen.
- Grupp och announcement kan stängas för nya meddelanden av serververifierad `message.moderate`-behörighet. Historiken ligger kvar.
- Global trådradering är ett explicit ärende: initiativtagaren och en separat behörig godkännare måste vara olika användare. Själva appliceringen är service-only.
- Cross-club- och integritetsmarkerade ärenden går via `teamzone_review` före serviceapplicering.
- Applicering raderar inga meddelande-, läs-, deltagar- eller notifieringsrader. Innehåll blir neutral tombstone, meddelanderevision/ordning och reply-referenser bevaras, filer dras tillbaka och notifieringspayload redigeras.
- Flutterytan erbjuder Dölj, Lämna och – när serverprojektionen uttryckligen tillåter det – Stäng.

## Verifierat lokalt

- Dart-format körd direkt med SDK-binären.
- Statisk kontraktsgrind täcker personlig livscykel, behörighetskontroll, tvåpersonerskrav, TeamZone-review och tombstone-invarianter.
- Ingen Supabase-liveändring eller produktionsprovisionering är gjord.

## Återstår

- PostgreSQL-runtime/advisors när Docker eller annan godkänd lokal databas finns.
- Flutter test/analyze om wrappern kan köras utan låsning.
- Fysisk flerrollsverifiering samt serviceoperator/kö under separat driftgodkännande.
