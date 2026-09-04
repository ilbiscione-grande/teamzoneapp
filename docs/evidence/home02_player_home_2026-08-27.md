# HOME-02 – Spelarens Hem

## Lokalt genomfört

- Spelaren får en separat hemprojektion som kräver player-roll i vald lagkontext och kopplar data till spelarens verifierade `club_person`.
- Lagkortet visar klubb, lag och medlemsantal utan administrativa åtgärder.
- Nästa aktivitet visar tid/plats och öppnar EventDetails.
- Endast spelarens egna aktuella kallelser projiceras. Korten visar aktuell status och kan besvaras med Kommer, Kanske eller Kan inte.
- Snabbsvar återanvänder CAL-07:s idempotenta mutationskontrakt med expected revision. Avböjande kräver strukturerad anledning och fritext endast för `other`.
- Player-svar skickar aldrig guardian `acting_as`; inga leader-, roster-, attendance- eller guardianadministrativa actions projiceras.
- Olästa relevanta lagmeddelanden visas som en säker räknare och genväg till inkorgen, inte som meddelandebody.
- Kontextbunden cachefallback märks explicit som inaktuell med senaste servergenereringstid. Gamla kallelser kan läsas men inte besvaras förrän färsk serverdata har hämtats.

## Verifierat lokalt

- `flutter test test/home02_player_home_test.dart test/home03_guardian_home_test.dart`: 9/9 passerar.
- `dart analyze lib test`: inga problem.
- Dart-format och statisk kontraktsgrind täcker person-/kontextisolering, egna kallelser, revisionssäker mutation, decline reason, säker stale-cache samt frånvaro av leader/guardian-actions.
- Ingen Supabase-liveändring eller produktionsprovisionering är gjord.

## Återstår

- PostgreSQL-runtime/advisors när en godkänd lokal databas är tillgänglig.
- Fysisk spelarverifiering av tre svar, stale revision, decline reason, deep links och mobil/tablet-layout.
