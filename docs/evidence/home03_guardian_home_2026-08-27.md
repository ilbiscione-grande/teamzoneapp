# HOME-03 – Vårdnadshavarens Hem

## Lokalt genomfört

- Guardian-hemsidan kräver guardian-roll i vald lagkontext och en verifierad kontokoppling till vårdnadshavarens `club_person`.
- Barnväljaren innehåller endast barn med aktiv, giltig guardian/custodian-relation och aktiv tilldelning i det valda laget.
- Servern avvisar ett explicit barn-ID som inte tillhör relationen eller lagkontexten; klientvalet är aldrig auktorisation.
- Kallelser filtreras till valt barn. Barnets namn visas både överst och direkt vid svarsknapparna.
- Varje snabbsvar skickar serverprojektionens `acting_as_person_id`, expected revision och strukturerad decline reason genom CAL-07-flödet och vidare till audit.
- Nästa event och meddelanderäknare begränsas till valt lags relationstillåtna kontext; ingen meddelandebody exponeras.

## Verifierat lokalt

- Dart-format och statisk kontraktsgrind täcker aktiv relation, barn-/lagisolering, synlig acting-as och mutationens acting-as/revision/decline reason.
- Ingen Supabase-liveändring eller produktionsprovisionering är gjord.

## Återstår

- PostgreSQL-runtime/advisors när en godkänd lokal databas är tillgänglig.
- Flutter test/analyze när wrappern kan slutföra utan låsning.
- Fysisk guardianverifiering med minst två barn, två lagkontexter, stale revision och avslutad relation.
