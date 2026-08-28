# HOME-02 – Spelarens Hem

## Lokalt genomfört

- Spelaren får en separat hemprojektion som kräver player-roll i vald lagkontext och kopplar data till spelarens verifierade `club_person`.
- Lagkortet visar klubb, lag och medlemsantal utan administrativa åtgärder.
- Nästa aktivitet visar tid/plats och öppnar EventDetails.
- Endast spelarens egna aktuella kallelser projiceras. Korten visar aktuell status och kan besvaras med Kommer, Kanske eller Kan inte.
- Snabbsvar återanvänder CAL-07:s idempotenta mutationskontrakt med expected revision. Avböjande kräver strukturerad anledning och fritext endast för `other`.
- Player-svar skickar aldrig guardian `acting_as`; inga leader-, roster-, attendance- eller guardianadministrativa actions projiceras.
- Olästa relevanta lagmeddelanden visas som en säker räknare och genväg till inkorgen, inte som meddelandebody.

## Verifierat lokalt

- Dart-format och statisk kontraktsgrind täcker person-/kontextisolering, egna kallelser, revisionssäker mutation, decline reason samt frånvaro av leader/guardian-actions.
- Ingen Supabase-liveändring eller produktionsprovisionering är gjord.

## Återstår

- PostgreSQL-runtime/advisors när en godkänd lokal databas är tillgänglig.
- Flutter test/analyze när wrappern kan slutföra utan låsning.
- Fysisk spelarverifiering av tre svar, stale revision, decline reason, deep links och mobil/tablet-layout.
